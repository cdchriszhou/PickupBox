#pragma once

#include <QMediaPlayer>
#include <QObject>
#include <QString>
#include <QUrl>
#include <QVector>
#include <atomic>
#include <deque>

class QAudioOutput;
class QThread;
class QTimer;
class LocalPcmPlayer;

class AudioEngine : public QObject
{
    Q_OBJECT
public:
    explicit AudioEngine(QObject *parent = nullptr);
    ~AudioEngine() override;

    QMediaPlayer *player() const { return m_player; }
    qint64 position() const;
    float volume() const { return m_userVolume; }
    void setVolume(float v);
    void setSleepFade(float gain01);
    void setMute(bool on);
    void setMegaBass(bool on);
    void setLoudness(bool on);
    void setDolby(bool on);
    void setTone(float bass, float mid, float treble, float balance);

    bool isStreaming() const { return m_streaming; }
    bool mute() const { return m_mute; }
    bool megaBass() const { return m_megaBass; }
    bool isPlaying() const;
    QString currentPath() const { return m_currentPath; }

public slots:
    void playFile(const QString &path);
    void openFile(const QString &path);
    void openUrl(const QUrl &url, const QString &title = {});
    void play();
    void pause();
    void stop();
    void seek(qint64 positionMs);
    void seekRelative(qint64 deltaMs);

signals:
    void levelsChanged(float left, float right);
    void waveformChanged(const QVector<float> &samples);
    void positionChanged(qint64 pos);
    void durationChanged(qint64 dur);
    void playingChanged(bool playing);
    void trackReady(const QString &name);
    void trackFinished();
    void errorOccurred(const QString &message);
    void statusMessage(const QString &message);

private slots:
    void emitLevels();
    void onPlayerError(QMediaPlayer::Error error, const QString &errorString);
    void onPlaybackStateChanged(QMediaPlayer::PlaybackState state);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);
    void onDurationChanged(qint64 dur);
    void watchdogTick();

private:
    void applyOutputGain();
    float effectiveVolume() const;
    void resetMeters();
    void ensureAudioOutput();
    void synthesizeMeters();
    void armWatchdog();
    void tryPlay();
    void beginNewSource();
    void rebuildPipeline();
    void wirePlayer();
    void log(const QString &line) const;
    void stopLocal();
    void stopMediaPlayer();
    int localToken() const { return m_localToken.load(std::memory_order_acquire); }
    void onLocalStarted(int token);
    void onLocalPlaying(int token, bool on);
    void onLocalPosition(int token, qint64 ms);
    void onLocalDuration(int token, qint64 ms);
    void onLocalFinished(int token);
    void onLocalFailed(int token, const QString &message);

    friend class LocalPcmPlayer;

    QMediaPlayer *m_player = nullptr;
    LocalPcmPlayer *m_local = nullptr;
    QThread *m_localThread = nullptr;
    QAudioOutput *m_audioOut = nullptr;
    QTimer *m_watchdog = nullptr;

    float m_liveL = 0;
    float m_liveR = 0;
    bool m_streaming = false;
    bool m_useLocal = false;
    bool m_localWanted = false;
    bool m_localPaused = false;
    bool m_forcePlayer = false;
    bool m_wantPlay = false;
    bool m_everPlayed = false;
    bool m_sourceReady = false; // setSource 完成前忽略 status/Loaded 误触发
    int m_sourceGen = 0;
    std::atomic<int> m_localToken{0};
    qint64 m_localPos = 0;
    int m_watchTries = 0;
    int m_stuckTicks = 0;
    int m_levelTick = 0;
    qint64 m_lastPos = -1;
    qint64 m_watchPos = -1;
    QString m_currentPath;
    std::deque<float> m_waveRing;

    float m_userVolume = 0.75f;
    float m_sleepFade = 1.f;
    bool m_mute = false;
    bool m_megaBass = false;
    bool m_loudness = false;
    float m_bass = 0.55f;
    float m_mid = 0.50f;
    float m_treble = 0.50f;
    float m_balance = 0.50f;
    bool m_dolby = false;
};
