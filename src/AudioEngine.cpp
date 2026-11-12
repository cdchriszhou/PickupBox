#include "AudioEngine.h"
#include "PaintKit.h"

#include <QAudioBuffer>
#include <QAudioDecoder>
#include <QAudioDevice>
#include <QAudioFormat>
#include <QAudioOutput>
#include <QAudioSink>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QMediaDevices>
#include <QIODevice>
#include <QTextStream>
#include <QThread>
#include <QTimer>
#include <QUrl>
#include <QtMath>
#include <utility>

// 本地文件不用 QMediaPlayer。Qt 6.8 FFmpeg 音频渲染把声卡缓冲卡在约 110ms，
// 并且把可听延迟硬压在 22–64ms：本地解码比实时快，缓冲一直被顶满，
// 大约每 400ms 就会改时钟丢掉一块样点，听感就是规律性卡顿。
// 网络流按实时到达，缓冲落在这个窗口里，所以电台是顺的。
// 本地改为 QAudioDecoder 拉取 PCM，写入约 450ms 的 QAudioSink，不再做丢样对时。
// 带内嵌封面的 MP3 里，封面是 ID3 的 APIC。Qt 6.8 的 QAudioDecoder 会把它当成视频流，
// 第一包读到封面就判定结束，一个 PCM 都没有。解码前先把 ID3v2 整段藏起来。

namespace {

// 把文件开头的 ID3v2 藏掉，位置 0 对应标签后面的音频帧。随机访问，方便 FFmpeg 回绕。
class Id3SkipDevice : public QIODevice
{
public:
    explicit Id3SkipDevice(const QString &path, QObject *parent = nullptr)
        : QIODevice(parent)
        , m_file(path)
    {
    }

    qint64 skipped() const { return m_skip; }

    bool open(OpenMode) override
    {
        if (isOpen())
            return true;
        if (!m_file.open(QIODevice::ReadOnly))
            return false;
        m_skip = id3v2Bytes(m_file);
        m_size = m_file.size() - m_skip;
        if (m_skip <= 0 || m_size <= 0 || !m_file.seek(m_skip)) {
            m_file.close();
            m_skip = 0;
            m_size = 0;
            return false;
        }
        return QIODevice::open(QIODevice::ReadOnly | QIODevice::Unbuffered);
    }

    void close() override
    {
        QIODevice::close();
        m_file.close();
    }

    bool isSequential() const override { return false; }

    qint64 size() const override { return m_size; }

    qint64 bytesAvailable() const override
    {
        return qMax<qint64>(0, m_size - QIODevice::pos()) + QIODevice::bytesAvailable();
    }

protected:
    qint64 readData(char *data, qint64 maxSize) override
    {
        if (maxSize <= 0)
            return 0;
        const qint64 remain = m_size - QIODevice::pos();
        if (remain <= 0)
            return 0;
        const qint64 n = m_file.read(data, qMin(maxSize, remain));
        return n;
    }

    qint64 writeData(const char *, qint64) override { return -1; }

    bool seek(qint64 pos) override
    {
        if (pos < 0 || pos > m_size)
            return false;
        if (!m_file.seek(m_skip + pos))
            return false;
        return QIODevice::seek(pos);
    }

private:
    static qint64 id3v2Bytes(QFile &file)
    {
        if (!file.seek(0))
            return 0;
        unsigned char h[10];
        if (file.read(reinterpret_cast<char *>(h), 10) != 10)
            return 0;
        if (h[0] != 'I' || h[1] != 'D' || h[2] != '3')
            return 0;
        if (h[3] < 2 || h[3] > 4)
            return 0;
        if ((h[6] | h[7] | h[8] | h[9]) & 0x80)
            return 0;
        const qint64 tag = (qint64(h[6]) << 21) | (qint64(h[7]) << 14) | (qint64(h[8]) << 7)
            | qint64(h[9]);
        const bool footer = (h[5] & 0x10) != 0;
        const qint64 total = 10 + tag + (footer ? 10 : 0);
        if (total <= 10 || total >= file.size())
            return 0;
        return total;
    }

    QFile m_file;
    qint64 m_skip = 0;
    qint64 m_size = 0;
};

} // namespace

namespace {
QString mediaStatusName(QMediaPlayer::MediaStatus s)
{
    switch (s) {
    case QMediaPlayer::NoMedia: return QStringLiteral("NoMedia");
    case QMediaPlayer::LoadingMedia: return QStringLiteral("Loading");
    case QMediaPlayer::LoadedMedia: return QStringLiteral("Loaded");
    case QMediaPlayer::StalledMedia: return QStringLiteral("Stalled");
    case QMediaPlayer::BufferingMedia: return QStringLiteral("Buffering");
    case QMediaPlayer::BufferedMedia: return QStringLiteral("Buffered");
    case QMediaPlayer::EndOfMedia: return QStringLiteral("EndOfMedia");
    case QMediaPlayer::InvalidMedia: return QStringLiteral("Invalid");
    default: return QString::number(int(s));
    }
}
} // namespace

class LocalPcmPlayer : public QObject
{
public:
    explicit LocalPcmPlayer(AudioEngine *owner, QObject *parent = nullptr)
        : QObject(parent)
        , m_owner(owner)
    {
    }

    ~LocalPcmPlayer() override
    {
        m_ignoreFinish = true;
        if (m_pump)
            m_pump->stop();
        if (m_decoder)
            m_decoder->stop();
        closeSink();
    }

    void startFile(const QString &path, int token, float gain)
    {
        // 连点下一首时，过期的请求直接丢掉，避免把声卡和译码器拆掉十几次
        if (!m_owner || token != m_owner->localToken())
            return;
        m_pullScheduled = false;
        m_inRead = false;
        m_inIdle = false;
        m_ignoreFinish = true;
        if (m_pump)
            m_pump->stop();
        destroyDecoder();
        m_ignoreFinish = false;
        m_pending.clear();
        m_readPos = 0;
        m_decodeDone = false;
        m_finishSent = false;
        m_lastWrite.invalidate();

        m_token = token;
        m_gain = gain;
        m_path = path;
        m_paused = false;
        m_decodeDone = false;
        m_finishSent = false;
        m_discardUntilUs = -1;
        m_originUs = 0;
        m_decodedCursorUs = 0;
        m_sessionWriteUs = 0;
        m_lastEmitPos = -1;
        m_underruns = 0;
        m_formatReady = false;
        m_pending.clear();
        m_readPos = 0;
        m_lastWrite.invalidate();

        // 声卡保持开着。每次切歌都 reset 再 start，Windows 上连续点几次后设备就不再出声。
        if (m_sink && m_sinkStarted)
            m_sinkBaseUs = m_sink->processedUSecs();
        else
            m_sinkBaseUs = 0;

        ensureObjects();
        if (token != m_owner->localToken())
            return;
        if (!m_decoder || !m_decoder->isSupported()) {
            failLater(QStringLiteral("本机解码器不可用"));
            return;
        }
        m_format = chooseFormat();
        if (!m_format.isValid()) {
            failLater(QStringLiteral("没有可用的音频输出设备"));
            return;
        }

        m_ignoreFinish = true;
        m_decoder->setAudioFormat(m_format);
        attachSource();
        m_ignoreFinish = false;
        m_pump->start();
        if (token != m_owner->localToken())
            return;
        m_decoder->start();
        if (token != m_owner->localToken())
            return;
        if (m_decoder->error() != QAudioDecoder::NoError) {
            failLater(m_decoder->errorString().isEmpty()
                          ? QStringLiteral("无法解码本地文件")
                          : m_decoder->errorString());
            return;
        }
        const QString pathCopy = path;
        const qint64 skipped = m_media ? m_media->skipped() : 0;
        post([owner = m_owner, token, pathCopy, skipped] {
            owner->log(QStringLiteral("local start %1 skipId3=%2").arg(pathCopy).arg(skipped));
            owner->onLocalStarted(token);
        });
    }

    void pausePlayback()
    {
        m_paused = true;
        if (m_pump)
            m_pump->stop();
        if (m_sink)
            m_sink->suspend();
        const int token = m_token;
        post([owner = m_owner, token] { owner->onLocalPlaying(token, false); });
    }

    void resumePlayback()
    {
        m_paused = false;
        if (m_sink && m_sink->state() == QAudio::SuspendedState)
            m_sink->resume();
        if (m_pump)
            m_pump->start();
        pullLimited();
        pump();
        const int token = m_token;
        post([owner = m_owner, token] { owner->onLocalPlaying(token, true); });
    }

    void seekMs(qint64 ms)
    {
        if (m_path.isEmpty())
            return;
        ensureObjects();
        if (!m_decoder)
            return;
        if (ms < 0)
            ms = 0;
        const bool paused = m_paused;
        m_discardUntilUs = ms * 1000;
        m_originUs = m_discardUntilUs;
        m_decodedCursorUs = 0;
        m_sessionWriteUs = 0;
        m_decodeDone = false;
        m_finishSent = false;
        m_lastEmitPos = -1;
        m_underruns = 0;
        m_pending.clear();
        m_readPos = 0;
        closeSink();
        m_paused = paused;

        m_ignoreFinish = true;
        m_decoder->stop();
        if (m_format.isValid())
            m_decoder->setAudioFormat(m_format);
        attachSource();
        m_ignoreFinish = false;
        if (!m_paused && m_pump)
            m_pump->start();
        m_decoder->start();
        const int token = m_token;
        post([owner = m_owner, token, ms] { owner->onLocalPosition(token, ms); });
    }

    // 设备空了或停了时重新 start。不 delete 声卡，避免 WASAPI 会话丢光。
    bool restartSinkIo()
    {
        if (!m_sink)
            return false;
        if (m_lastIoRestart.isValid() && m_lastIoRestart.elapsed() < 200)
            return m_io != nullptr;
        const qint64 played = qMax<qint64>(0, m_sink->processedUSecs() - m_sinkBaseUs);
        m_originUs += played;
        m_sink->blockSignals(true);
        m_sink->setVolume(m_gain);
        m_io = m_sink->start();
        m_sink->blockSignals(false);
        m_lastIoRestart.start();
        m_sinkBaseUs = 0;
        m_sessionWriteUs = 0;
        m_sinkStarted = m_io != nullptr;
        if (!m_sinkStarted)
            closeSink();
        return m_sinkStarted;
    }

    void setGain(float gain)
    {
        m_gain = gain;
        if (m_sink)
            m_sink->setVolume(gain);
    }

    void halt()
    {
        m_pullScheduled = false;
        m_inRead = false;
        m_inIdle = false;
        m_ignoreFinish = true;
        if (m_pump)
            m_pump->stop();
        destroyDecoder();
        m_ignoreFinish = false;
        closeSink();
        m_pending.clear();
        m_readPos = 0;
        m_decodeDone = false;
        m_finishSent = true;
        m_lastWrite.invalidate();
    }

private:
    template <typename F>
    void post(F &&fn)
    {
        if (!m_owner)
            return;
        QMetaObject::invokeMethod(m_owner, std::forward<F>(fn), Qt::QueuedConnection);
    }

    void destroyDecoder()
    {
        if (!m_decoder)
            return;
        QObject::disconnect(m_decoder, nullptr, this, nullptr);
        m_decoder->stop();
        m_decoder->setParent(nullptr);
        delete m_decoder;
        m_decoder = nullptr;
        closeSkipDevice();
    }

    void closeSkipDevice()
    {
        if (!m_media)
            return;
        m_media->close();
        m_media->setParent(nullptr);
        delete m_media;
        m_media = nullptr;
    }

    // 有 ID3v2（封面通常在里面）就用跳过标签的设备；否则仍按路径打开。
    void attachSource()
    {
        closeSkipDevice();
        if (!m_decoder)
            return;
        auto *dev = new Id3SkipDevice(m_path, this);
        if (dev->open(QIODevice::ReadOnly)) {
            m_media = dev;
            m_decoder->setSourceDevice(m_media);
            return;
        }
        delete dev;
        m_decoder->setSource(QUrl::fromLocalFile(m_path));
    }

    void ensureObjects()
    {
        if (m_decoder)
            return;
        m_decoder = new QAudioDecoder(this);
        connect(m_decoder, &QAudioDecoder::bufferReady, this, [this] { pullLimited(); });
        connect(m_decoder, &QAudioDecoder::finished, this, [this] { onDecoderFinished(); });
        connect(m_decoder, &QAudioDecoder::durationChanged, this, [this](qint64 dur) {
            if (dur <= 0)
                return;
            const int token = m_token;
            post([owner = m_owner, token, dur] { owner->onLocalDuration(token, dur); });
        });
        connect(m_decoder, qOverload<QAudioDecoder::Error>(&QAudioDecoder::error), this,
                [this](QAudioDecoder::Error) { onDecoderError(); });

        m_pump = new QTimer(this);
        m_pump->setInterval(12);
        connect(m_pump, &QTimer::timeout, this, [this] { onPump(); });
    }

    static QAudioFormat chooseFormat()
    {
        const QAudioDevice dev = QMediaDevices::defaultAudioOutput();
        if (dev.isNull())
            return {};
        const QAudioFormat pref = dev.preferredFormat();
        QAudioFormat fmt;
        fmt.setSampleRate(pref.sampleRate() > 0 ? pref.sampleRate() : 48000);
        fmt.setSampleFormat(pref.sampleFormat() != QAudioFormat::Unknown
                                ? pref.sampleFormat()
                                : QAudioFormat::Int16);
        fmt.setChannelConfig(QAudioFormat::ChannelConfigStereo);
        if (dev.isFormatSupported(fmt))
            return fmt;
        if (pref.isValid() && dev.isFormatSupported(pref))
            return pref;
        return {};
    }

    void failLater(const QString &msg)
    {
        const int token = m_token;
        QTimer::singleShot(0, this, [this, token, msg] {
            if (token != m_token)
                return;
            halt();
            post([owner = m_owner, token, msg] { owner->onLocalFailed(token, msg); });
        });
    }

    void onDecoderError()
    {
        if (m_ignoreFinish || !m_decoder)
            return;
        if (m_decoder->error() == QAudioDecoder::NoError)
            return;
        const QString msg = m_decoder->errorString().isEmpty()
                                ? QStringLiteral("无法解码本地文件")
                                : m_decoder->errorString();
        failLater(msg);
    }

    void onDecoderFinished()
    {
        if (m_ignoreFinish)
            return;
        m_decodeDone = true;
        // read() 内部会同步触发 finished，此时当前块还没放进队列
        if (m_inRead)
            return;
        pump();
        checkEnd();
    }

    void onPump()
    {
        if (m_paused)
            return;
        pump();
        if (!m_decodeDone && pendingUs() < 800000)
            pullLimited();
        emitPos();
        checkEnd();
    }

    qint64 pendingBytes() const
    {
        return qMax<qint64>(0, m_pending.size() - m_readPos);
    }

    qint64 pendingUs() const
    {
        if (!m_format.isValid() || m_format.bytesPerFrame() <= 0)
            return 0;
        const qint64 bytes = pendingBytes();
        if (bytes <= 0)
            return 0;
        return m_format.durationForBytes(qint32(qMin<qint64>(bytes, 0x7fffffff)));
    }

    bool pendingEmpty() const { return m_readPos >= m_pending.size(); }

    void pullLimited()
    {
        if (m_inRead || m_paused || !m_decoder || m_decodeDone)
            return;
        if (pendingUs() >= 1500000)
            return;

        constexpr qint64 kSeekSliceUs = 250000;
        qint64 skippedUs = 0;
        while (m_decoder->bufferAvailable() && pendingUs() < 1500000 && skippedUs < kSeekSliceUs) {
            m_inRead = true;
            const QAudioBuffer buf = m_decoder->read();
            m_inRead = false;
            if (!buf.isValid() || buf.byteCount() <= 0)
                break;
            if (!acceptFormat(buf.format()))
                return;
            const qint64 startUs = buf.startTime() >= 0 ? buf.startTime() : m_decodedCursorUs;
            const qint64 durUs = m_format.durationForBytes(
                qint32(qMin<qint64>(buf.byteCount(), 0x7fffffff)));
            m_decodedCursorUs = startUs + qMax<qint64>(0, durUs);
            const bool skipping = m_discardUntilUs >= 0;
            appendBuffer(buf, startUs, durUs);
            if (skipping)
                skippedUs += qMax<qint64>(0, durUs);
        }

        if (!m_paused && !m_decodeDone && m_decoder->bufferAvailable()
            && (pendingUs() < 1500000 || m_discardUntilUs >= 0) && !m_pullScheduled) {
            m_pullScheduled = true;
            QTimer::singleShot(0, this, [this] {
                m_pullScheduled = false;
                pullLimited();
            });
        }
        pump();
        if (m_decodeDone)
            checkEnd();
    }

    bool acceptFormat(const QAudioFormat &actual)
    {
        if (!actual.isValid() || actual.bytesPerFrame() <= 0) {
            failLater(QStringLiteral("解码格式无效"));
            return false;
        }
        if (m_formatReady)
            return true;
        const QAudioDevice dev = QMediaDevices::defaultAudioOutput();
        if (dev.isNull() || !dev.isFormatSupported(actual)) {
            failLater(QStringLiteral("声卡不支持解码后的格式"));
            return false;
        }
        if (m_sink && m_sinkStarted && m_sink->format() != actual)
            closeSink();
        m_format = actual;
        m_formatReady = true;
        return true;
    }

    void appendBuffer(const QAudioBuffer &buf, qint64 startUs, qint64 durUs)
    {
        const char *data = buf.constData<char>();
        int size = int(qMin<qint64>(buf.byteCount(), 0x7fffffff));
        int skip = 0;
        if (m_discardUntilUs >= 0) {
            if (startUs + durUs <= m_discardUntilUs)
                return;
            if (startUs < m_discardUntilUs) {
                const int bpf = qMax(1, m_format.bytesPerFrame());
                skip = m_format.bytesForDuration(m_discardUntilUs - startUs);
                skip -= skip % bpf;
                if (skip < 0)
                    skip = 0;
                if (skip > size)
                    skip = size;
            }
            m_discardUntilUs = -1;
            m_originUs = startUs + (skip > 0 ? m_format.durationForBytes(skip) : 0);
        }
        if (!data || skip >= size)
            return;
        if (m_readPos > 262144) {
            m_pending.remove(0, m_readPos);
            m_readPos = 0;
        }
        m_pending.append(data + skip, size - skip);
    }

    void openSink()
    {
        if (m_sinkStarted || m_paused || !m_format.isValid())
            return;
        const QAudioDevice dev = QMediaDevices::defaultAudioOutput();
        if (dev.isNull()) {
            failLater(QStringLiteral("未检测到音频输出设备"));
            return;
        }
        auto *sink = new QAudioSink(dev, m_format, this);
        const qint32 bytes = m_format.bytesForDuration(450000);
        if (bytes > 0)
            sink->setBufferSize(bytes);
        sink->setVolume(m_gain);
        m_sink = sink;
        connect(sink, &QAudioSink::stateChanged, this, [this, sink](QAudio::State state) {
            if (sink != m_sink)
                return;
            if (state == QAudio::IdleState)
                onSinkIdle();
        });
        m_io = sink->start();
        m_sinkBaseUs = 0;
        m_sessionWriteUs = 0;
        if (!m_io) {
            failLater(QStringLiteral("无法打开声卡"));
            return;
        }
        m_sinkStarted = true;
        const qint64 bufUs = m_format.durationForBytes(
            qint32(qMin<qint64>(sink->bufferSize(), 0x7fffffff)));
        const int token = m_token;
        post([owner = m_owner, token, bufUs, rate = m_format.sampleRate(), ch = m_format.channelCount()] {
            owner->log(QStringLiteral("local sink bufferUs=%1 rate=%2 ch=%3")
                           .arg(bufUs)
                           .arg(rate)
                           .arg(ch));
        });
    }

    void closeSink()
    {
        m_io = nullptr;
        m_sinkStarted = false;
        if (!m_sink)
            return;
        QAudioSink *old = m_sink;
        m_sink = nullptr;
        old->blockSignals(true);
        old->stop();
        old->setParent(nullptr);
        delete old;
    }

    void pump()
    {
        if (m_paused || !m_format.isValid())
            return;
        if (!m_sinkStarted) {
            // 声卡还在时直接接着写；只有第一次才稍微攒一点，避免刚打开就欠载
            if (pendingUs() >= 60000 || (m_decodeDone && !pendingEmpty()))
                openSink();
            if (!m_sinkStarted)
                return;
        } else if (!pendingEmpty() && m_sink) {
            const auto st = m_sink->state();
            // Idle 且缓冲还有空位时，接着写就会恢复。只有设备停住或缓冲卡死才重新 start。
            if (st == QAudio::StoppedState
                || (st == QAudio::IdleState && m_sessionWriteUs > 0 && m_sink->bytesFree() <= 0)) {
                if (!restartSinkIo())
                    return;
            }
        }
        if (!m_io || !m_sink)
            return;
        const int bpf = m_format.bytesPerFrame();
        if (bpf <= 0)
            return;
        while (!pendingEmpty()) {
            int freeBytes = int(qMin<qint64>(m_sink->bytesFree(), 0x7fffffff));
            freeBytes -= freeBytes % bpf;
            int have = int(pendingBytes());
            have -= have % bpf;
            if (freeBytes <= 0 || have <= 0)
                break;
            const int n = qMin(freeBytes, have);
            const qint64 wrote = m_io->write(m_pending.constData() + m_readPos, n);
            if (wrote <= 0)
                break;
            const int written = int(wrote) - int(wrote) % bpf;
            if (written <= 0)
                break;
            m_readPos += written;
            m_sessionWriteUs += m_format.durationForBytes(written);
            m_lastWrite.start();
            if (written < wrote)
                break;
        }
    }

    void onSinkIdle()
    {
        if (m_inIdle || m_paused || !m_sinkStarted)
            return;
        if (m_sessionWriteUs <= 0)
            return;
        if (pendingEmpty()) {
            checkEnd();
            return;
        }
        // 不能在声卡回调里重启自己，拖到下一轮事件
        m_inIdle = true;
        QTimer::singleShot(0, this, [this] {
            if (!m_inIdle || m_paused)
                return;
            m_inIdle = false;
            if (!m_sink || pendingEmpty()) {
                checkEnd();
                return;
            }
            if (!restartSinkIo())
                return;
            pump();
        });
    }

    void checkEnd()
    {
        if (m_finishSent || m_paused || !m_decodeDone || !pendingEmpty())
            return;
        if (!m_sinkStarted) {
            if (m_decodedCursorUs <= 0) {
                failLater(QStringLiteral("文件没有可播放的音频"));
                return;
            }
            m_finishSent = true;
            if (m_pump)
                m_pump->stop();
            const int token = m_token;
            post([owner = m_owner, token] { owner->onLocalFinished(token); });
            return;
        }
        const bool idle = m_sink->state() == QAudio::IdleState;
        // processedUSecs 在 Windows 上几乎贴着已写入的数据走，不能拿它判断“已经听完”。
        // 声卡里还有约 450ms。等设备空闲，或最后一次写入过去半秒，再切下一首。
        const bool tailDone = m_lastWrite.isValid() && m_lastWrite.elapsed() >= 500;
        if (!idle && !tailDone)
            return;
        m_finishSent = true;
        if (m_pump)
            m_pump->stop();
        const int token = m_token;
        post([owner = m_owner, token] { owner->onLocalFinished(token); });
    }

    void emitPos()
    {
        if (!m_sinkStarted || !m_sink)
            return;
        const qint64 played = qMax<qint64>(0, m_sink->processedUSecs() - m_sinkBaseUs);
        const qint64 pos = (m_originUs + played) / 1000;
        const qint64 delta = pos - m_lastEmitPos;
        if (m_lastEmitPos >= 0 && delta < 80 && delta > -80)
            return;
        m_lastEmitPos = pos;
        const int token = m_token;
        post([owner = m_owner, token, pos] { owner->onLocalPosition(token, pos); });
    }

    AudioEngine *m_owner = nullptr;
    QAudioDecoder *m_decoder = nullptr;
    Id3SkipDevice *m_media = nullptr;
    QAudioSink *m_sink = nullptr;
    QIODevice *m_io = nullptr;
    QTimer *m_pump = nullptr;
    QAudioFormat m_format;
    QByteArray m_pending;
    QString m_path;
    int m_token = 0;
    int m_readPos = 0;
    int m_underruns = 0;
    float m_gain = 0.75f;
    QElapsedTimer m_lastWrite;
    QElapsedTimer m_lastIoRestart;
    qint64 m_originUs = 0;
    qint64 m_decodedCursorUs = 0;
    qint64 m_discardUntilUs = -1;
    qint64 m_sessionWriteUs = 0;
    qint64 m_sinkBaseUs = 0;
    qint64 m_lastEmitPos = -1;
    bool m_paused = false;
    bool m_decodeDone = false;
    bool m_finishSent = true;
    bool m_ignoreFinish = false;
    bool m_sinkStarted = false;
    bool m_formatReady = false;
    bool m_inRead = false;
    bool m_pullScheduled = false;
    bool m_inIdle = false;
};

template <typename F>
void postToLocal(LocalPcmPlayer *local, F &&fn)
{
    if (!local)
        return;
    QMetaObject::invokeMethod(local, std::forward<F>(fn), Qt::QueuedConnection);
}

AudioEngine::AudioEngine(QObject *parent)
    : QObject(parent)
{
    m_waveRing = std::deque<float>(64, 0.f);
    m_localThread = new QThread(this);
    m_localThread->setObjectName(QStringLiteral("local-pcm"));
    m_local = new LocalPcmPlayer(this);
    m_local->moveToThread(m_localThread);
    m_localThread->start(QThread::HighPriority);

    m_audioOut = new QAudioOutput(this);
    m_player = new QMediaPlayer(this);
    wirePlayer();
    ensureAudioOutput();
    setVolume(0.75f);

    auto *tick = new QTimer(this);
    tick->setInterval(50);
    connect(tick, &QTimer::timeout, this, &AudioEngine::emitLevels);
    tick->start();

    m_watchdog = new QTimer(this);
    m_watchdog->setInterval(250);
    connect(m_watchdog, &QTimer::timeout, this, &AudioEngine::watchdogTick);
}

AudioEngine::~AudioEngine()
{
    if (m_local && m_localThread && m_localThread->isRunning()) {
        QThread *mainThread = QThread::currentThread();
        QMetaObject::invokeMethod(
            m_local,
            [local = m_local, mainThread] {
                local->halt();
                local->moveToThread(mainThread);
            },
            Qt::BlockingQueuedConnection);
        delete m_local;
        m_local = nullptr;
        m_localThread->quit();
        m_localThread->wait(3000);
    }
}

void AudioEngine::log(const QString &line) const
{
    QFile f(QDir::temp().filePath(QStringLiteral("fh_kaok_audio.log")));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return;
    QTextStream ts(&f);
    ts << QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss.zzz"))
       << ' ' << line << '\n';
}

void AudioEngine::wirePlayer()
{
    if (!m_player)
        return;
    connect(m_player, &QMediaPlayer::positionChanged, this, &AudioEngine::positionChanged);
    connect(m_player, &QMediaPlayer::durationChanged, this, &AudioEngine::onDurationChanged);
    connect(m_player, &QMediaPlayer::playbackStateChanged, this, &AudioEngine::onPlaybackStateChanged);
    connect(m_player, &QMediaPlayer::errorOccurred, this, &AudioEngine::onPlayerError);
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, &AudioEngine::onMediaStatusChanged);
}

void AudioEngine::rebuildPipeline()
{
    // 保留：仅在极端情况下由外部调用。日常切歌不再重建，避免 Windows 音频会话丢失。
    if (m_player) {
        QObject::disconnect(m_player, nullptr, this, nullptr);
        m_player->stop();
        m_player->setAudioOutput(nullptr);
        delete m_player;
        m_player = nullptr;
    }
    m_player = new QMediaPlayer(this);
    wirePlayer();
    if (!m_audioOut)
        m_audioOut = new QAudioOutput(this);
    ensureAudioOutput();
    applyOutputGain();
}

bool AudioEngine::isPlaying() const
{
    if (m_useLocal)
        return m_localWanted && !m_localPaused;
    return m_player && m_player->playbackState() == QMediaPlayer::PlayingState;
}

qint64 AudioEngine::position() const
{
    if (m_useLocal)
        return m_localPos;
    return m_player ? m_player->position() : 0;
}

void AudioEngine::ensureAudioOutput()
{
    if (!m_audioOut)
        m_audioOut = new QAudioOutput(this);

    const QAudioDevice device = QMediaDevices::defaultAudioOutput();
    if (device.isNull()) {
        emit statusMessage(tr("未检测到音频输出设备"));
        log(QStringLiteral("NO_AUDIO_DEVICE"));
        return;
    }
    if (m_audioOut->device() != device)
        m_audioOut->setDevice(device);
    if (m_player && m_player->audioOutput() != m_audioOut)
        m_player->setAudioOutput(m_audioOut);
    applyOutputGain();
}

float AudioEngine::effectiveVolume() const
{
    if (m_mute)
        return 0.f;
    float v = m_userVolume;
    if (m_loudness)
        v = PaintKit::clamp01(v * 1.06f + (1.f - v) * 0.08f);
    if (m_megaBass)
        v = PaintKit::clamp01(v * 1.14f);
    // 三段均衡的简易增益：中音略抬，低音影响更大
    v = PaintKit::clamp01(v * (0.86f + 0.22f * m_bass + 0.08f * m_mid + 0.06f * m_treble));
    if (m_dolby)
        v = PaintKit::clamp01(v * 0.97f); // 降噪听感略收一点毛刺
    v = PaintKit::clamp01(v * m_sleepFade);
    return qMax(0.05f, v);
}

void AudioEngine::applyOutputGain()
{
    const float gain = effectiveVolume();
    if (m_audioOut) {
        m_audioOut->setMuted(false);
        m_audioOut->setVolume(m_mute ? 0.f : gain);
    }
    if (m_local && m_useLocal) {
        postToLocal(m_local, [local = m_local, gain] { local->setGain(gain); });
    }
}

void AudioEngine::setVolume(float v)
{
    m_userVolume = PaintKit::clamp01(v);
    applyOutputGain();
}

void AudioEngine::setSleepFade(float gain01)
{
    m_sleepFade = PaintKit::clamp01(gain01);
    applyOutputGain();
}

void AudioEngine::setMute(bool on)
{
    m_mute = on;
    applyOutputGain();
}

void AudioEngine::setMegaBass(bool on)
{
    m_megaBass = on;
    applyOutputGain();
}

void AudioEngine::setLoudness(bool on)
{
    m_loudness = on;
    applyOutputGain();
}

void AudioEngine::setDolby(bool on)
{
    m_dolby = on;
    applyOutputGain();
}

void AudioEngine::setTone(float bass, float mid, float treble, float balance)
{
    m_bass = PaintKit::clamp01(bass);
    m_mid = PaintKit::clamp01(mid);
    m_treble = PaintKit::clamp01(treble);
    m_balance = PaintKit::clamp01(balance);
    applyOutputGain();
    Q_UNUSED(m_balance);
}

void AudioEngine::resetMeters()
{
    m_liveL = m_liveR = 0;
    m_lastPos = -1;
    m_waveRing.assign(64, 0.f);
}

void AudioEngine::armWatchdog()
{
    m_watchTries = 0;
    m_watchdog->start();
}

void AudioEngine::beginNewSource()
{
    ++m_sourceGen;
    m_everPlayed = false;
    m_wantPlay = true;
    m_sourceReady = false;
}

void AudioEngine::tryPlay()
{
    if (m_useLocal)
        return;
    if (!m_wantPlay || !m_player)
        return;
    if (m_player->source().isEmpty())
        return;
    const auto st = m_player->mediaStatus();
    // 僵尸 Playing（状态 Playing 但正在 Loading / 进度一直为 0）时仍要再踢 play
    if (isPlaying()
        && st != QMediaPlayer::LoadingMedia
        && (m_everPlayed || m_player->position() > 0))
        return;
    ensureAudioOutput();
    applyOutputGain();
    log(QStringLiteral("tryPlay status=%1 outVol=%2 muted=%3 pos=%4")
            .arg(mediaStatusName(st))
            .arg(m_audioOut ? m_audioOut->volume() : -1)
            .arg(m_audioOut ? int(m_audioOut->isMuted()) : -1)
            .arg(m_player->position()));
    m_player->play();
}

void AudioEngine::playFile(const QString &path)
{
    const QFileInfo info(path);
    if (!info.exists() || !info.isFile()) {
        m_wantPlay = false;
        emit errorOccurred(tr("文件不存在: %1").arg(path));
        return;
    }
    if (info.size() <= 0) {
        m_wantPlay = false;
        emit errorOccurred(tr("文件为空: %1").arg(info.fileName()));
        return;
    }

    QString abs = QFileInfo(info.absoluteFilePath()).canonicalFilePath();
    if (abs.isEmpty())
        abs = info.absoluteFilePath();

    m_streaming = false;
    m_sleepFade = 1.f;
    m_mute = false;
    if (m_userVolume < 0.4f)
        m_userVolume = 0.75f;

    log(QStringLiteral("playFile %1").arg(abs));

    if (!m_forcePlayer) {
        m_currentPath = abs;
        resetMeters();
        m_useLocal = true;
        m_localWanted = true;
        m_localPaused = false;
        m_localPos = 0;
        stopMediaPlayer();
        emit trackReady(info.fileName());
        emit statusMessage(tr("打开  ·  %1").arg(info.fileName()));
        ++m_localToken;
        const int token = m_localToken;
        const float gain = effectiveVolume();
        postToLocal(m_local, [local = m_local, abs, token, gain] {
            local->startFile(abs, token, gain);
        });
        return;
    }

    // 同一文件：直接从头播（仅 QMediaPlayer 兜底路径）
    if (abs == m_currentPath && m_player && !m_player->source().isEmpty()
        && m_player->mediaStatus() != QMediaPlayer::NoMedia
        && m_player->mediaStatus() != QMediaPlayer::InvalidMedia) {
        beginNewSource();
        resetMeters();
        ensureAudioOutput();
        applyOutputGain();
        m_player->setPosition(0);
        m_sourceReady = true;
        emit trackReady(info.fileName());
        tryPlay();
        armWatchdog();
        return;
    }

    m_currentPath = abs;
    resetMeters();
    beginNewSource();
    m_stuckTicks = 0;
    m_watchPos = -1;
    ensureAudioOutput();
    applyOutputGain();

    // 门闩关闭：stop()/换源前的 Loaded 不得触发 tryPlay
    const int gen = m_sourceGen;
    const QString pending = m_currentPath;
    const QString name = info.fileName();
    emit trackReady(name);
    emit statusMessage(tr("打开  ·  %1").arg(name));
    m_player->stop();
    QTimer::singleShot(0, this, [this, gen, pending]() {
        if (m_sourceGen != gen || !m_wantPlay || !m_player)
            return;
        log(QStringLiteral("setSource deferred %1").arg(pending));
        m_player->setSource(QUrl::fromLocalFile(pending));
        m_sourceReady = true;
        armWatchdog();
    });
}

void AudioEngine::openFile(const QString &path)
{
    playFile(path);
}

void AudioEngine::openUrl(const QUrl &url, const QString &title)
{
    if (!url.isValid()) {
        m_wantPlay = false;
        emit errorOccurred(tr("无效的电台地址"));
        return;
    }

    stopLocal();
    m_useLocal = false;
    m_streaming = true;
    m_sleepFade = 1.f;
    m_mute = false;
    if (m_userVolume < 0.4f)
        m_userVolume = 0.75f;
    m_currentPath.clear();
    resetMeters();
    beginNewSource();
    ensureAudioOutput();
    applyOutputGain();

    m_player->setSource(url);
    m_sourceReady = true;
    emit trackReady(title.isEmpty() ? url.host() : title);
    emit statusMessage(tr("连接电台  ·  %1").arg(title.isEmpty() ? url.host() : title));
    armWatchdog();
}

void AudioEngine::play()
{
    if (m_useLocal) {
        m_sleepFade = 1.f;
        m_mute = false;
        if (m_userVolume < 0.4f)
            m_userVolume = 0.75f;
        applyOutputGain();
        if (m_localPaused) {
            m_localPaused = false;
            m_localWanted = true;
            postToLocal(m_local, [local = m_local] { local->resumePlayback(); });
            return;
        }
        if (!m_localWanted && !m_currentPath.isEmpty()) {
            playFile(m_currentPath);
            return;
        }
        return;
    }

    m_wantPlay = true;
    m_sleepFade = 1.f;
    m_mute = false;
    if (m_userVolume < 0.4f)
        m_userVolume = 0.75f;
    applyOutputGain();

    if (!m_player || m_player->source().isEmpty()) {
        if (!m_currentPath.isEmpty()) {
            playFile(m_currentPath);
            return;
        }
        emit statusMessage(tr("没有可播放的媒体"));
        return;
    }
    tryPlay();
    armWatchdog();
}

void AudioEngine::pause()
{
    if (m_useLocal) {
        m_localPaused = true;
        if (m_local)
            postToLocal(m_local, [local = m_local] { local->pausePlayback(); });
        return;
    }
    m_wantPlay = false;
    m_watchdog->stop();
    if (m_player)
        m_player->pause();
}

void AudioEngine::stop()
{
    stopLocal();
    m_useLocal = false;
    stopMediaPlayer();
    m_everPlayed = false;
    resetMeters();
    emit levelsChanged(0, 0);
    emit waveformChanged({});
}

void AudioEngine::seek(qint64 positionMs)
{
    const qint64 ms = qMax<qint64>(0, positionMs);
    if (m_useLocal && m_local) {
        m_localWanted = true;
        postToLocal(m_local, [local = m_local, ms] { local->seekMs(ms); });
        m_localPos = ms;
        emit positionChanged(ms);
        return;
    }
    if (m_player)
        m_player->setPosition(ms);
}

void AudioEngine::seekRelative(qint64 deltaMs)
{
    if (m_useLocal) {
        seek(m_localPos + deltaMs);
        return;
    }
    if (!m_player)
        return;
    seek(m_player->position() + deltaMs);
}

void AudioEngine::stopLocal()
{
    m_localWanted = false;
    m_localPaused = false;
    ++m_localToken;
    if (!m_local || !m_localThread || !m_localThread->isRunning())
        return;
    QMetaObject::invokeMethod(m_local, [local = m_local] { local->halt(); },
                              Qt::BlockingQueuedConnection);
}

void AudioEngine::stopMediaPlayer()
{
    m_wantPlay = false;
    m_sourceReady = false;
    ++m_sourceGen;
    if (m_watchdog)
        m_watchdog->stop();
    if (!m_player)
        return;
    if (m_player->playbackState() == QMediaPlayer::StoppedState && m_player->source().isEmpty())
        return;
    m_player->stop();
    m_player->setSource(QUrl());
}

void AudioEngine::onLocalStarted(int token)
{
    if (token != localToken() || !m_useLocal)
        return;
    emit playingChanged(true);
    emit statusMessage(tr("播放中  ·  音量 %1%").arg(int(qRound(effectiveVolume() * 100))));
}

void AudioEngine::onLocalPlaying(int token, bool on)
{
    if (token != localToken() || !m_useLocal)
        return;
    m_localPaused = !on;
    if (on)
        m_localWanted = true;
    emit playingChanged(on);
}

void AudioEngine::onLocalPosition(int token, qint64 ms)
{
    if (token != localToken() || !m_useLocal)
        return;
    m_localPos = ms;
    emit positionChanged(ms);
}

void AudioEngine::onLocalDuration(int token, qint64 ms)
{
    if (token != localToken() || !m_useLocal || ms <= 0)
        return;
    emit durationChanged(ms);
}

void AudioEngine::onLocalFinished(int token)
{
    if (token != localToken() || !m_useLocal)
        return;
    log(QStringLiteral("local end token=%1").arg(token));
    m_localWanted = false;
    emit playingChanged(false);
    QTimer::singleShot(0, this, [this, token] {
        if (token != localToken() || !m_useLocal)
            return;
        emit trackFinished();
    });
}

void AudioEngine::onLocalFailed(int token, const QString &message)
{
    if (token != localToken())
        return;
    ++m_localToken;
    log(QStringLiteral("local failed: %1").arg(message));
    m_useLocal = false;
    m_localWanted = false;
    m_localPaused = false;
    if (m_local && m_localThread && m_localThread->isRunning()) {
        QMetaObject::invokeMethod(m_local, [local = m_local] { local->halt(); },
                                  Qt::BlockingQueuedConnection);
    }
    if (m_currentPath.isEmpty()) {
        emit errorOccurred(message);
        return;
    }
    // 解码器打不开时退回 QMediaPlayer，避免本地文件完全无声
    m_forcePlayer = true;
    const QString path = m_currentPath;
    playFile(path);
    m_forcePlayer = false;
}

void AudioEngine::watchdogTick()
{
    if (m_useLocal || !m_wantPlay) {
        m_watchdog->stop();
        return;
    }

    // Playing 但进度不走 → 僵尸态，继续看门狗
    if (isPlaying() && m_player) {
        const qint64 pos = m_player->position();
        if (pos != m_watchPos) {
            m_watchPos = pos;
            m_stuckTicks = 0;
            if (pos > 0) {
                m_watchdog->stop();
                return;
            }
        } else {
            ++m_stuckTicks;
        }
        if (m_stuckTicks < 8) // ~2s
            return;
        log(QStringLiteral("watchdog STUCK playing pos=%1 — reload").arg(pos));
        m_stuckTicks = 0;
        m_everPlayed = false;
        m_player->stop();
        m_player->setSource(QUrl::fromLocalFile(m_currentPath));
        tryPlay();
        return;
    }

    ++m_watchTries;
    const auto st = m_player ? m_player->mediaStatus() : QMediaPlayer::NoMedia;
    log(QStringLiteral("watchdog try=%1 status=%2").arg(m_watchTries).arg(mediaStatusName(st)));

    if (st == QMediaPlayer::InvalidMedia && m_watchTries >= 3) {
        m_watchdog->stop();
        m_wantPlay = false;
        emit errorOccurred(tr("无法解码: %1")
                               .arg(m_currentPath.isEmpty()
                                        ? tr("当前媒体")
                                        : QFileInfo(m_currentPath).fileName()));
        return;
    }

    tryPlay();

    if (m_watchTries == 4 && !m_currentPath.isEmpty() && !isPlaying() && m_player) {
        const auto ms = m_player->mediaStatus();
        if (ms != QMediaPlayer::LoadedMedia && ms != QMediaPlayer::BufferedMedia) {
            emit statusMessage(tr("重试装载  ·  %1").arg(QFileInfo(m_currentPath).fileName()));
            m_player->setSource(QUrl::fromLocalFile(m_currentPath));
        }
        tryPlay();
    }

    if (m_watchTries >= 16 && !isPlaying()) {
        m_watchdog->stop();
        m_wantPlay = false;
        emit errorOccurred(
            tr("无法开始播放 (status=%1): %2")
                .arg(mediaStatusName(st))
                .arg(m_currentPath.isEmpty()
                         ? tr("未知文件")
                         : QFileInfo(m_currentPath).fileName()));
    }
}

void AudioEngine::synthesizeMeters()
{
    if (!m_useLocal && !m_player)
        return;
    const qint64 pos = position();
    const float moving = (pos != m_lastPos) ? 1.f : 0.35f;
    m_lastPos = pos;
    const float t = float(m_levelTick);
    const float kick = qMax(0.f, qSin(t * 0.21f));
    const float hat = qAbs(qSin(t * 0.73f + 1.2f));
    const float body = 0.45f + 0.55f * qAbs(qSin(t * 0.11f + float(pos) * 0.002f));
    const float volScale = 0.25f + 0.55f * m_userVolume;
    m_liveL = PaintKit::clamp01((0.08f + 0.22f * body + 0.18f * kick) * volScale * moving);
    m_liveR = PaintKit::clamp01((0.07f + 0.20f * body + 0.16f * hat) * volScale * moving);
    if (!m_waveRing.empty()) {
        m_waveRing.pop_front();
        m_waveRing.push_back(PaintKit::clamp01(
            (0.10f + 0.28f * body + 0.20f * kick * (1.f - hat * 0.4f)) * volScale * moving));
    }
}

void AudioEngine::emitLevels()
{
    ++m_levelTick;
    if (!isPlaying()) {
        m_liveL *= 0.82f;
        m_liveR *= 0.82f;
        if (m_liveL < 0.01f && m_liveR < 0.01f)
            m_liveL = m_liveR = 0;
        if (!m_waveRing.empty()) {
            m_waveRing.pop_front();
            m_waveRing.push_back(0.f);
        }
        emit levelsChanged(m_liveL, m_liveR);
        if ((m_levelTick & 1) == 0)
            emit waveformChanged(QVector<float>(m_waveRing.begin(), m_waveRing.end()));
        return;
    }
    synthesizeMeters();
    emit levelsChanged(m_liveL, m_liveR);
    if ((m_levelTick & 1) == 0)
        emit waveformChanged(QVector<float>(m_waveRing.begin(), m_waveRing.end()));
}

void AudioEngine::onPlayerError(QMediaPlayer::Error, const QString &errorString)
{
    if (m_useLocal)
        return;
    log(QStringLiteral("error want=%1 empty=%2 text=%3")
            .arg(int(m_wantPlay))
            .arg(int(errorString.isEmpty()))
            .arg(errorString));
    if (!m_wantPlay)
        return;
    if (errorString.isEmpty())
        return;

    m_watchdog->stop();
    m_wantPlay = false;
    const QString msg = tr("播放失败: %1").arg(errorString)
                        + (m_currentPath.isEmpty()
                               ? QString()
                               : QStringLiteral("  ·  ") + QFileInfo(m_currentPath).fileName());
    emit errorOccurred(msg);
}

void AudioEngine::onDurationChanged(qint64 dur)
{
    if (m_useLocal)
        return;
    emit durationChanged(dur);
    if (dur > 0 && m_wantPlay && !isPlaying())
        tryPlay();
}

void AudioEngine::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    if (m_useLocal || !m_player)
        return;

    log(QStringLiteral("status=%1 want=%2 ready=%3 ever=%4 pos=%5")
            .arg(mediaStatusName(status))
            .arg(int(m_wantPlay))
            .arg(int(m_sourceReady))
            .arg(int(m_everPlayed))
            .arg(m_player->position()));

    if (!m_sourceReady)
        return;

    if (status == QMediaPlayer::InvalidMedia) {
        if (!m_wantPlay || m_player->source().isEmpty())
            return;
        m_watchdog->stop();
        m_wantPlay = false;
        emit errorOccurred(tr("无法解码%1")
                               .arg(m_currentPath.isEmpty()
                                        ? tr("该文件")
                                        : (QStringLiteral(": ") + QFileInfo(m_currentPath).fileName())));
        return;
    }

    if (m_wantPlay
        && (status == QMediaPlayer::LoadedMedia
            || status == QMediaPlayer::BufferedMedia
            || status == QMediaPlayer::BufferingMedia)) {
        tryPlay();
        return;
    }

    if (status == QMediaPlayer::EndOfMedia && !m_streaming && m_wantPlay) {
        if (!m_everPlayed)
            return;
        m_watchdog->stop();
        m_everPlayed = false;
        const int gen = m_sourceGen;
        QTimer::singleShot(0, this, [this, gen]() {
            if (m_sourceGen != gen || !m_wantPlay)
                return;
            emit trackFinished();
        });
    }
}

void AudioEngine::onPlaybackStateChanged(QMediaPlayer::PlaybackState state)
{
    if (m_useLocal)
        return;
    const bool playing = (state == QMediaPlayer::PlayingState);
    log(QStringLiteral("playbackState=%1").arg(int(state)));
    if (playing) {
        m_everPlayed = true;
        m_watchdog->stop();
        ensureAudioOutput();
        applyOutputGain();
        emit statusMessage(tr("播放中  ·  音量 %1%").arg(int(qRound(effectiveVolume() * 100))));
    }
    emit playingChanged(playing);
}
