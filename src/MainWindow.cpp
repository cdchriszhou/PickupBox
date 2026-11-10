#include "MainWindow.h"
#include "AudioEngine.h"
#include "RadioBrowser.h"

#include <QMediaPlayer>
#include <QAction>
#include <QDir>
#include <QDirIterator>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QCursor>
#include <QKeySequence>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QMimeData>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QStatusBar>
#include <QStringConverter>
#include <QTextStream>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>
#include <QtMath>
#include <algorithm>

namespace {
const QStringList kAudioSuffixes = {
    QStringLiteral("mp3"), QStringLiteral("wav"), QStringLiteral("flac"),
    QStringLiteral("ogg"), QStringLiteral("m4a"), QStringLiteral("aac"),
    QStringLiteral("wma")
};
int g_consecutivePlayFails = 0;

bool isAudioFile(const QString &path)
{
    return kAudioSuffixes.contains(QFileInfo(path).suffix().toLower());
}

constexpr float kLockWindow = 0.18f;

float clamp01(float v)
{
    return v < 0.f ? 0.f : (v > 1.f ? 1.f : v);
}
} // namespace

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
{
    setWindowTitle(QStringLiteral("拾音盒子"));
    resize(1040, 720);
    setMinimumSize(920, 640);
    setAcceptDrops(true);

    m_engine = new AudioEngine(this);
    m_deck = new CassetteDeckWidget;
    m_radioBrowser = new RadioBrowser(this);

    auto *root = new QWidget;
    auto *layout = new QVBoxLayout(root);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);
    layout->addWidget(m_deck, 1);
    setCentralWidget(root);

    statusBar()->showMessage(tr("CITY 选城市（在线全量台） · POWER→ON · EJECT 装带"));
    initRegions();
    buildMenu();

    connect(m_radioBrowser, &RadioBrowser::fetchStarted, this, [this](const QString &name) {
        statusBar()->showMessage(tr("正在从 Radio Browser 加载「%1」全部电台…").arg(name));
    });
    connect(m_radioBrowser, &RadioBrowser::stationsReady, this, &MainWindow::onRemoteStationsReady);
    connect(m_radioBrowser, &RadioBrowser::fetchFailed, this, &MainWindow::onRemoteFetchFailed);

    connect(m_deck, &CassetteDeckWidget::openRequested, this, &MainWindow::openFolder);
    connect(m_deck, &CassetteDeckWidget::playPressed, this, [this]() {
        // 有磁带时一律播本地；仅无磁带且收音机开着才走电台
        if (!m_playlist.isEmpty()) {
            playCurrent();
            return;
        }
        if (m_radioPower) {
            if (m_lockedStation < 0) {
                statusBar()->showMessage(tr("请先调谐到电台频率"));
                return;
            }
            const RadioStation &st = m_stations[m_lockedStation];
            enterRadioMode();
            m_engine->openUrl(st.url, st.name);
            statusBar()->showMessage(
                tr("播放中  ·  FM %1  ·  %2")
                    .arg(st.freq, 0, 'f', 1)
                    .arg(st.name));
            return;
        }
        statusBar()->showMessage(tr("未装带 — 请点 EJECT 导入 MP3，或拨收音机 POWER→ON"));
    });
    connect(m_deck, &CassetteDeckWidget::pausePressed, m_engine, &AudioEngine::pause);
    connect(m_deck, &CassetteDeckWidget::stopPressed, m_engine, &AudioEngine::stop);
    connect(m_deck, &CassetteDeckWidget::rewindPressed, this, [this]() {
        // 有磁带且非收音机模式 → 上一曲；否则 FM 切台
        if (!m_playlist.isEmpty() && !m_radioMode) {
            playPrev();
            return;
        }
        if (m_radioMode || m_radioPower) {
            onRadioSeek(-1);
            return;
        }
        playPrev();
    });
    connect(m_deck, &CassetteDeckWidget::forwardPressed, this, [this]() {
        if (!m_playlist.isEmpty() && !m_radioMode) {
            playNext();
            return;
        }
        if (m_radioMode || m_radioPower) {
            onRadioSeek(+1);
            return;
        }
        playNext();
    });
    connect(m_deck, &CassetteDeckWidget::seekRequested, this, &MainWindow::onSeekRatio);
    connect(m_deck, &CassetteDeckWidget::volumeChanged, m_engine, &AudioEngine::setVolume);
    connect(m_deck, &CassetteDeckWidget::sleepFadeChanged, m_engine, &AudioEngine::setSleepFade);
    connect(m_deck, &CassetteDeckWidget::muteToggled, m_engine, &AudioEngine::setMute);
    connect(m_deck, &CassetteDeckWidget::megaBassToggled, m_engine, &AudioEngine::setMegaBass);
    connect(m_deck, &CassetteDeckWidget::loudnessToggled, m_engine, &AudioEngine::setLoudness);
    connect(m_deck, &CassetteDeckWidget::dolbyToggled, m_engine, &AudioEngine::setDolby);
    connect(m_deck, &CassetteDeckWidget::toneChanged, m_engine, &AudioEngine::setTone);
    connect(m_deck, &CassetteDeckWidget::sleepFinished, this, [this]() {
        m_engine->stop();
        if (m_radioPower)
            onRadioPower(false);
        statusBar()->showMessage(tr("睡眠模式结束 — 已自动关机"), 8000);
    });
    connect(m_deck, &CassetteDeckWidget::sleepRemainingChanged, this, [this](int sec) {
        if (sec <= 0)
            return;
        // 仅在整分钟或刚设定时提示，避免每秒刷状态栏
        if (sec % 60 == 0 || sec == 15 * 60 || sec == 30 * 60 || sec == 60 * 60 || sec == 90 * 60) {
            statusBar()->showMessage(
                tr("睡眠定时  %1 分钟后自动关机").arg((sec + 59) / 60), 4000);
        }
    });
    connect(m_deck, &CassetteDeckWidget::frequencyChanged, this, &MainWindow::onFrequencyChanged);
    connect(m_deck, &CassetteDeckWidget::radioSeekRequested, this, &MainWindow::onRadioSeek);
    connect(m_deck, &CassetteDeckWidget::radioPowerToggled, this, &MainWindow::onRadioPower);
    connect(m_deck, &CassetteDeckWidget::radioRegionPressed, this, &MainWindow::onRadioRegionPressed);
    connect(m_deck, &CassetteDeckWidget::trackSelected, this, &MainWindow::onTrackSelected);
    connect(m_deck, &CassetteDeckWidget::radioStationSelected, this, [this](int index) {
        if (index < 0 || index >= m_stations.size())
            return;
        if (!m_radioPower)
            onRadioPower(true);
        applyFrequency(m_stations[index].freq, true);
    });
    connect(m_deck, &CassetteDeckWidget::playModeChanged, this, [this](CassetteDeckWidget::PlayMode mode) {
        QString tip;
        switch (mode) {
        case CassetteDeckWidget::PlayMode::SingleLoop:
            tip = tr("单曲循环");
            break;
        case CassetteDeckWidget::PlayMode::Random:
            tip = tr("随机播放");
            break;
        case CassetteDeckWidget::PlayMode::AllLoop:
        default:
            tip = tr("全部循环");
            break;
        }
        statusBar()->showMessage(tr("播放模式  ·  %1").arg(tip), 3000);
    });

    connect(m_engine, &AudioEngine::levelsChanged, m_deck, &CassetteDeckWidget::setLevels);
    connect(m_engine, &AudioEngine::waveformChanged, m_deck, &CassetteDeckWidget::setWaveform);
    connect(m_engine, &AudioEngine::trackReady, this, &MainWindow::onTrack);
    connect(m_engine, &AudioEngine::positionChanged, this, &MainWindow::onPosition);
    connect(m_engine, &AudioEngine::durationChanged, this, &MainWindow::onDuration);
    connect(m_engine, &AudioEngine::playingChanged, this, &MainWindow::onPlaying);
    connect(m_engine, &AudioEngine::trackFinished, this, [this]() {
        if (m_radioMode)
            return;
        if (m_deck->playMode() == CassetteDeckWidget::PlayMode::SingleLoop) {
            m_engine->seek(0);
            m_engine->play();
            return;
        }
        playNext();
    });
    connect(m_engine, &AudioEngine::errorOccurred, this, &MainWindow::onError);
    connect(m_engine, &AudioEngine::statusMessage, this, [this](const QString &msg) {
        statusBar()->showMessage(msg, 2500);
    });

    m_engine->setVolume(0.75f);
    setRadioPower(false);
    // 默认拉成都全量台（不自动播放）
    applyRegion(QStringLiteral("chengdu"), false);

    setStyleSheet(QStringLiteral(
        "QMainWindow { background: #0a0a0c; }"
        "QStatusBar { color: #8a8a90; background: #0e0e10; border-top: 1px solid #222; }"
        "QMenuBar { background: #121214; color: #c8c8cc; border-bottom: 1px solid #1e1e22; }"
        "QMenuBar::item:selected { background: #2a2a30; }"
        "QMenu { background: #1a1a1e; color: #ddd; border: 1px solid #333; }"
        "QMenu::item:selected { background: #33333a; }"));
}

void MainWindow::initRegions()
{
    m_regions = RadioBrowser::defaultRegions();
}

void MainWindow::applyRegion(const QString &regionId, bool autoTune)
{
    const int ri = regionIndex(regionId);
    if (ri < 0)
        return;

    m_regionId = regionId;
    m_lockedStation = -1;
    m_pendingAutoTune = autoTune;
    m_stations.clear();
    m_deck->setRadioMarkers({}, {});
    m_deck->setRadioStationNames({});
    m_deck->setRadioRegionName(m_regions[ri].name);
    if (autoTune)
        m_deck->setMediaTab(CassetteDeckWidget::MediaTab::Radio);
    rebuildRadioStationMenu();

    m_radioBrowser->fetchRegion(m_regions[ri]);
}

void MainWindow::applyRemoteStations(const QVector<RemoteStation> &remote, bool autoTune)
{
    m_stations.clear();
    m_stations.reserve(remote.size());

    const float fMin = 87.5f;
    const float fMax = 108.0f;
    const int n = remote.size();
    for (int i = 0; i < n; ++i) {
        RadioStation s;
        s.freq = (n <= 1) ? 95.7f : (fMin + (fMax - fMin) * float(i) / float(n - 1));
        s.freq = std::round(s.freq * 10.f) / 10.f;
        s.name = remote[i].name;
        // 刻度短标签：两位序号，避免中文挤在一起
        s.shortLabel = QString::number(i + 1).rightJustified(2, QLatin1Char('0'));
        s.url = remote[i].url;
        s.regionId = m_regionId;
        m_stations.append(s);
    }

    QVector<float> freqs;
    QStringList labels;
    QStringList names;
    freqs.reserve(m_stations.size());
    names.reserve(m_stations.size());
    for (const RadioStation &s : m_stations) {
        freqs.append(s.freq);
        labels.append(s.shortLabel);
        names.append(s.name);
    }
    m_deck->setRadioMarkers(freqs, labels);
    m_deck->setRadioStationNames(names);
    if (autoTune)
        m_deck->setMediaTab(CassetteDeckWidget::MediaTab::Radio);
    rebuildRadioStationMenu();

    if (m_stations.isEmpty()) {
        statusBar()->showMessage(tr("该地区暂无可用电台"));
        return;
    }

    applyFrequency(m_stations.first().freq, autoTune && m_radioPower);

    const int ri = regionIndex(m_regionId);
    statusBar()->showMessage(
        tr("%1  ·  已载入 %2 个电台（Radio Browser 全量）")
            .arg(ri >= 0 ? m_regions[ri].name : m_regionId)
            .arg(m_stations.size()));
}

void MainWindow::onRemoteStationsReady(const QString &regionId, const QVector<RemoteStation> &stations)
{
    if (regionId != m_regionId)
        return;
    applyRemoteStations(stations, m_pendingAutoTune);
    m_pendingAutoTune = false;
}

void MainWindow::onRemoteFetchFailed(const QString &regionId, const QString &message)
{
    if (regionId != m_regionId)
        return;
    m_pendingAutoTune = false;
    statusBar()->showMessage(message);
}

int MainWindow::regionIndex(const QString &regionId) const
{
    for (int i = 0; i < m_regions.size(); ++i) {
        if (m_regions[i].id == regionId)
            return i;
    }
    return -1;
}

void MainWindow::onRadioRegionPressed()
{
    QMenu menu(this);
    auto *cn = menu.addMenu(tr("中国城市"));
    auto *world = menu.addMenu(tr("海外城市"));
    for (const RadioRegionDef &r : m_regions) {
        QMenu *parent = (r.countryCode == QLatin1String("CN")
                         || r.id == QLatin1String("hongkong")
                         || r.id == QLatin1String("taipei")
                         || r.id == QLatin1String("china"))
                            ? cn
                            : world;
        auto *act = parent->addAction(r.name);
        act->setCheckable(true);
        act->setChecked(r.id == m_regionId);
        const QString id = r.id;
        connect(act, &QAction::triggered, this, [this, id]() {
            applyRegion(id, true);
        });
    }
    menu.exec(QCursor::pos());
}

void MainWindow::rebuildRadioStationMenu()
{
    if (!m_radioStationMenu)
        return;
    m_radioStationMenu->clear();
    if (m_stations.isEmpty()) {
        m_radioStationMenu->addAction(tr("（尚未加载 / 加载中）"))->setEnabled(false);
        return;
    }
    for (const RadioStation &s : m_stations) {
        auto *act = m_radioStationMenu->addAction(
            QStringLiteral("%1  %2 MHz").arg(s.name).arg(s.freq, 0, 'f', 1));
        const float freq = s.freq;
        connect(act, &QAction::triggered, this, [this, freq]() {
            if (!m_radioPower)
                onRadioPower(true);
            applyFrequency(freq, true);
        });
    }
}

void MainWindow::buildMenu()
{
    auto *fileMenu = menuBar()->addMenu(tr("文件"));

    auto *folderAct = fileMenu->addAction(tr("打开目录（批量装带）…"));
    folderAct->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+O")));
    connect(folderAct, &QAction::triggered, this, &MainWindow::openFolder);

    auto *openAct = fileMenu->addAction(tr("打开音频…"));
    openAct->setShortcut(QKeySequence::Open);
    connect(openAct, &QAction::triggered, this, &MainWindow::openFile);

    fileMenu->addSeparator();
    auto *quitAct = fileMenu->addAction(tr("退出"));
    quitAct->setShortcut(QKeySequence::Quit);
    connect(quitAct, &QAction::triggered, this, &QWidget::close);

    auto *radioMenu = menuBar()->addMenu(tr("电台"));
    auto *powerAct = radioMenu->addAction(tr("打开 / 关闭收音机"));
    connect(powerAct, &QAction::triggered, this, [this]() {
        onRadioPower(!m_radioPower);
    });
    radioMenu->addSeparator();

    auto *regionMenu = radioMenu->addMenu(tr("城市 / 地区"));
    auto *cn = regionMenu->addMenu(tr("中国城市"));
    auto *world = regionMenu->addMenu(tr("海外城市"));
    for (const RadioRegionDef &r : m_regions) {
        QMenu *parent = (r.countryCode == QLatin1String("CN")
                         || r.id == QLatin1String("hongkong")
                         || r.id == QLatin1String("taipei")
                         || r.id == QLatin1String("china"))
                            ? cn
                            : world;
        auto *act = parent->addAction(r.name);
        const QString id = r.id;
        connect(act, &QAction::triggered, this, [this, id]() {
            applyRegion(id, true);
        });
    }

    m_radioStationMenu = radioMenu->addMenu(tr("当前地区电台"));
    rebuildRadioStationMenu();

    auto *helpMenu = menuBar()->addMenu(tr("帮助"));
    connect(helpMenu->addAction(tr("听音须知")), &QAction::triggered, this, [this]() {
        QMessageBox::information(
            this, tr("听音须知"),
            tr("把这里当成一间缩小的听音室，会更合适。\n\n"
               "【磁带】\n"
               "点 EJECT / OPEN，或把文件夹拖进来——\n"
               "像把一叠碟片轻轻推进仓门。\n\n"
               "【收音机】\n"
               "先选 CITY（城市），等电台落满刻度；\n"
               "再拨 POWER → ON，让声波醒来。\n\n"
               "【功放】\n"
               "MEGA BASS 是重低音，BASS / TREBLE 是音色，\n"
               "MUTE 是短暂的沉默，LOUDNESS 适合夜深人静。\n\n"
               "愿频谱的琥珀光，陪您把歌听完。"));
    });
    connect(helpMenu->addAction(tr("关于拾音盒子")), &QAction::triggered, this, &MainWindow::about);
}

QStringList MainWindow::collectAudioFiles(const QString &dirPath)
{
    QStringList files;
    QDirIterator it(dirPath, QDir::Files | QDir::Readable | QDir::NoSymLinks,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString path = it.next();
        if (isAudioFile(path))
            files.append(path);
    }
    files.sort(Qt::CaseInsensitive);
    return files;
}

void MainWindow::enterTapeMode()
{
    m_radioMode = false;
    m_lockedStation = -1;
    m_deck->setSourceMode(QStringLiteral("TAPE"));
}

void MainWindow::enterRadioMode()
{
    m_radioMode = true;
    m_deck->setSourceMode(QStringLiteral("FM"));
}

void MainWindow::setRadioPower(bool on)
{
    m_radioPower = on;
    m_deck->setRadioPower(on);
}

int MainWindow::nearestStation(float mhz, float *distanceOut) const
{
    int best = -1;
    float bestDist = 999.f;
    for (int i = 0; i < m_stations.size(); ++i) {
        const float d = qAbs(m_stations[i].freq - mhz);
        if (d < bestDist) {
            bestDist = d;
            best = i;
        }
    }
    if (distanceOut)
        *distanceOut = bestDist;
    return best;
}

void MainWindow::applyFrequency(float mhz, bool autoPlay)
{
    m_frequency = mhz;
    m_deck->setRadioFrequency(mhz);

    float dist = 999.f;
    const int idx = nearestStation(mhz, &dist);
    const bool locked = (idx >= 0 && dist <= kLockWindow);
    const float signal = locked ? clamp01(1.f - dist / kLockWindow)
                                : clamp01(0.22f - dist * 0.35f);

    // 关机时只更新刻度/指示，不拉流、不清播放列表
    if (!m_radioPower) {
        if (locked)
            m_deck->setRadioStation(m_stations[idx].name, true, qMax(0.4f, signal));
        else
            m_deck->setRadioStation(QString(), false, signal);
        return;
    }

    enterRadioMode();

    if (locked) {
        const RadioStation &st = m_stations[idx];
        m_deck->setRadioStation(st.name, true, qMax(0.4f, signal));
        if (m_lockedStation != idx) {
            m_lockedStation = idx;
            m_engine->openUrl(st.url, st.name);
            if (autoPlay)
                m_engine->play();
            statusBar()->showMessage(
                tr("FM %1 MHz  ·  %2").arg(st.freq, 0, 'f', 1).arg(st.name));
        } else if (autoPlay) {
            m_engine->play();
        }
    } else {
        m_lockedStation = -1;
        m_deck->setRadioStation(QString(), false, signal);
        if (m_engine->isStreaming())
            m_engine->stop();
        statusBar()->showMessage(tr("FM %1 MHz  ·  调谐中…").arg(mhz, 0, 'f', 1));
    }
}

void MainWindow::onFrequencyChanged(float mhz)
{
    applyFrequency(mhz, m_radioPower);
}

void MainWindow::onRadioSeek(int direction)
{
    if (m_stations.isEmpty())
        return;
    int idx = nearestStation(m_frequency);
    if (idx < 0)
        idx = 0;
    // If already locked on a station, jump to neighbor; else snap to nearest then step
    float dist = 0.f;
    nearestStation(m_frequency, &dist);
    if (dist <= kLockWindow)
        idx = qBound(0, idx + direction, m_stations.size() - 1);
    else if (direction > 0)
        idx = qMin(m_stations.size() - 1, idx + (m_stations[idx].freq < m_frequency ? 1 : 0));
    else
        idx = qMax(0, idx - (m_stations[idx].freq > m_frequency ? 1 : 0));

    applyFrequency(m_stations[idx].freq, m_radioPower);
}

void MainWindow::onRadioPower(bool on)
{
    if (on) {
        setRadioPower(true);
        applyFrequency(m_frequency, true);
        if (m_lockedStation >= 0) {
            statusBar()->showMessage(
                tr("收音机开启  ·  FM %1  ·  %2")
                    .arg(m_stations[m_lockedStation].freq, 0, 'f', 1)
                    .arg(m_stations[m_lockedStation].name));
        } else {
            statusBar()->showMessage(tr("收音机开启  ·  请调谐到电台"));
        }
        return;
    }

    m_engine->stop();
    m_lockedStation = -1;
    setRadioPower(false);
    if (!m_playlist.isEmpty()) {
        enterTapeMode();
        syncDeckPlaylist();
        statusBar()->showMessage(tr("收音机已关闭  ·  已回到磁带模式"));
    } else {
        m_radioMode = false;
        m_deck->setSourceMode(QStringLiteral("FM"));
        statusBar()->showMessage(tr("收音机已关闭 — 拨到 ON 再打开"));
    }
}

void MainWindow::openFolder()
{
    const QString dir = QFileDialog::getExistingDirectory(
        this, tr("选择磁带目录（批量导入 MP3）"), QString(),
        QFileDialog::ShowDirsOnly | QFileDialog::ReadOnly);
    if (dir.isEmpty())
        return;

    const QStringList files = collectAudioFiles(dir);
    if (files.isEmpty()) {
        QMessageBox::information(this, tr("空目录"),
                                 tr("目录中未找到 MP3 / 音频文件：\n%1").arg(dir));
        return;
    }
    loadPlaylist(files);
}

void MainWindow::openFile()
{
    const QStringList paths = QFileDialog::getOpenFileNames(
        this, tr("装入磁带（可多选）"), QString(),
        tr("音频文件 (*.mp3 *.wav *.flac *.ogg *.m4a *.aac *.wma);;MP3 (*.mp3);;所有文件 (*.*)"));
    if (!paths.isEmpty())
        loadPlaylist(paths);
}

void MainWindow::loadFile(const QString &path)
{
    loadPlaylist({path});
}

void MainWindow::loadPlaylist(const QStringList &paths, int startIndex)
{
    QStringList clean;
    clean.reserve(paths.size());
    for (const QString &p : paths) {
        if (QFileInfo::exists(p) && isAudioFile(p))
            clean.append(QFileInfo(p).absoluteFilePath());
    }
    if (clean.isEmpty()) {
        QMessageBox::warning(this, tr("无法装带"), tr("没有可用的音频文件。"));
        return;
    }

    setRadioPower(false);
    enterTapeMode();
    m_playlist = clean;
    m_playlistIndex = qBound(0, startIndex, m_playlist.size() - 1);
    syncDeckPlaylist();
    // 同步刷新命中区，保证立刻可点 PLAY
    m_deck->repaint();
    statusBar()->showMessage(
        tr("LOADED  %1 首  ·  %2")
            .arg(m_playlist.size())
            .arg(QFileInfo(m_playlist[m_playlistIndex]).fileName()));
    // 文件对话框关闭后稍后再播，避开设备/焦点时序问题
    QTimer::singleShot(80, this, [this]() {
        if (!m_playlist.isEmpty())
            playCurrent();
    });
}

void MainWindow::syncDeckPlaylist()
{
    QStringList titles;
    titles.reserve(m_playlist.size());
    for (const QString &p : m_playlist)
        titles.append(QFileInfo(p).completeBaseName());
    m_deck->setPlaylist(titles, m_playlistIndex);
    m_deck->setMediaTab(CassetteDeckWidget::MediaTab::Cover);
}

void MainWindow::loadLyricsForCurrent()
{
    if (m_playlistIndex < 0 || m_playlistIndex >= m_playlist.size()) {
        m_deck->setLyrics({});
        return;
    }
    const QFileInfo info(m_playlist[m_playlistIndex]);
    const QString lrc = info.absolutePath() + QLatin1Char('/') + info.completeBaseName() + QStringLiteral(".lrc");
    m_deck->setLyrics(parseLrcFile(lrc));
    m_deck->setCoverArt(QPixmap()); // regenerate procedural cover for this track
    m_deck->setPlaylistIndex(m_playlistIndex);
}

QVector<LyricLine> MainWindow::parseLrcFile(const QString &path)
{
    QVector<LyricLine> lines;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return lines;
    QTextStream in(&f);
    in.setEncoding(QStringConverter::Utf8);
    const QRegularExpression re(QStringLiteral(R"(\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\])"));
    while (!in.atEnd()) {
        const QString raw = in.readLine().trimmed();
        if (raw.isEmpty())
            continue;
        QRegularExpressionMatchIterator it = re.globalMatch(raw);
        QString text = raw;
        text.replace(re, QString());
        text = text.trimmed();
        if (text.isEmpty())
            continue;
        while (it.hasNext()) {
            const QRegularExpressionMatch m = it.next();
            const int min = m.captured(1).toInt();
            const int sec = m.captured(2).toInt();
            QString frac = m.captured(3);
            while (frac.size() < 3)
                frac.append(QLatin1Char('0'));
            if (frac.size() > 3)
                frac = frac.left(3);
            LyricLine line;
            line.timeMs = qint64(min) * 60000 + qint64(sec) * 1000 + frac.toInt();
            line.text = text;
            lines.append(line);
        }
    }
    std::sort(lines.begin(), lines.end(),
              [](const LyricLine &a, const LyricLine &b) { return a.timeMs < b.timeMs; });
    return lines;
}

void MainWindow::onTrackSelected(int index)
{
    if (index < 0 || index >= m_playlist.size())
        return;
    m_playlistIndex = index;
    playCurrent();
}

void MainWindow::playCurrent()
{
    if (m_playlistIndex < 0 || m_playlistIndex >= m_playlist.size())
        return;

    // 只关收音机标志，不要走 onRadioPower(false)->stop()，以免清掉随后的播放意图
    if (m_radioPower) {
        m_radioPower = false;
        m_deck->setRadioPower(false);
        m_lockedStation = -1;
    }
    enterTapeMode();
    loadLyricsForCurrent();
    m_engine->setMute(false);
    m_deck->setMute(false);
    m_engine->setSleepFade(1.f);
    const float vol = 0.75f;
    m_engine->setVolume(vol);
    m_deck->setVolume(vol);

    const QString path = m_playlist[m_playlistIndex];
    const int idx = m_playlistIndex;
    statusBar()->showMessage(tr("装带播放  ·  %1").arg(QFileInfo(path).fileName()), 3000);
    m_engine->playFile(path);
    // 不在 Loading 阶段立刻 play（会触发 FFmpeg 伪 PlayingState）。
    // LoadedMedia / watchdog 负责开播；仅作兜底延迟补踢。
    QTimer::singleShot(500, this, [this, idx, path]() {
        if (m_playlistIndex != idx || m_playlist.isEmpty())
            return;
        if (m_playlist[m_playlistIndex] != path)
            return;
        if (!m_engine->isPlaying())
            m_engine->play();
    });
}

void MainWindow::playNext()
{
    if (m_radioMode || m_playlist.isEmpty())
        return;

    const auto mode = m_deck->playMode();
    if (mode == CassetteDeckWidget::PlayMode::Random) {
        if (m_playlist.size() == 1) {
            m_engine->seek(0);
            m_engine->play();
            return;
        }
        int next = m_playlistIndex;
        while (next == m_playlistIndex)
            next = QRandomGenerator::global()->bounded(m_playlist.size());
        m_playlistIndex = next;
    } else {
        // 全部循环（及切歌）：末尾回到第一首
        if (m_playlistIndex + 1 >= m_playlist.size())
            m_playlistIndex = 0;
        else
            ++m_playlistIndex;
    }

    playCurrent();
    m_deck->setPlaylistIndex(m_playlistIndex);
    statusBar()->showMessage(
        tr("%1 / %2  ·  %3")
            .arg(m_playlistIndex + 1)
            .arg(m_playlist.size())
            .arg(QFileInfo(m_playlist[m_playlistIndex]).fileName()));
}

void MainWindow::playPrev()
{
    if (m_radioMode || m_playlist.isEmpty())
        return;

    if (m_deck->playMode() == CassetteDeckWidget::PlayMode::Random) {
        if (m_playlist.size() == 1) {
            m_engine->seek(0);
            return;
        }
        int prev = m_playlistIndex;
        while (prev == m_playlistIndex)
            prev = QRandomGenerator::global()->bounded(m_playlist.size());
        m_playlistIndex = prev;
    } else if (m_playlistIndex <= 0) {
        m_playlistIndex = m_playlist.size() - 1;
    } else {
        --m_playlistIndex;
    }

    playCurrent();
    m_deck->setPlaylistIndex(m_playlistIndex);
    statusBar()->showMessage(
        tr("%1 / %2  ·  %3")
            .arg(m_playlistIndex + 1)
            .arg(m_playlist.size())
            .arg(QFileInfo(m_playlist[m_playlistIndex]).fileName()));
}

void MainWindow::onTrack(const QString &name)
{
    if (m_radioMode) {
        m_deck->setTrackName(name);
        setWindowTitle(QStringLiteral("拾音盒子 — FM %1 — %2")
                           .arg(m_frequency, 0, 'f', 1)
                           .arg(name));
        return;
    }
    const QString title = m_playlist.size() > 1
        ? QStringLiteral("%1  [%2/%3]").arg(name).arg(m_playlistIndex + 1).arg(m_playlist.size())
        : name;
    m_deck->setTrackName(title);
    setWindowTitle(QStringLiteral("拾音盒子 — %1").arg(title));
}

void MainWindow::onPosition(qint64 pos)
{
    if (m_radioMode)
        return;
    if (m_duration > 0)
        m_deck->setProgress(float(pos) / float(m_duration));
    m_deck->setTimeText(QStringLiteral("%1 / %2").arg(fmtMs(pos), fmtMs(m_duration)));
}

void MainWindow::onDuration(qint64 dur)
{
    if (m_radioMode)
        return;
    m_duration = dur;
    m_deck->setTimeText(QStringLiteral("%1 / %2").arg(fmtMs(m_engine->position()), fmtMs(dur)));
}

void MainWindow::onPlaying(bool playing)
{
    m_deck->setPlaying(playing);
    if (playing && !m_radioMode && m_playlistIndex >= 0 && m_playlistIndex < m_playlist.size()) {
        g_consecutivePlayFails = 0;
        statusBar()->showMessage(
            tr("播放中  ·  %1 / %2  ·  %3")
                .arg(m_playlistIndex + 1)
                .arg(m_playlist.size())
                .arg(QFileInfo(m_playlist[m_playlistIndex]).fileName()),
            2500);
    }
}

void MainWindow::onSeekRatio(float ratio)
{
    if (m_radioMode)
        return;
    if (m_duration > 0)
        m_engine->seek(qint64(m_duration * ratio));
}

void MainWindow::onError(const QString &message)
{
    // 不再自动跳曲：切歌时的瞬态错误曾被连环 skip，表现为「下一首没声音」
    g_consecutivePlayFails = 0;
    statusBar()->showMessage(message, 8000);
    if (!m_radioMode)
        QMessageBox::warning(this, tr("播放错误"), message);
}

void MainWindow::about()
{
    QMessageBox::information(
        this, tr("关于拾音盒子"),
        tr("拾音盒子\n"
           "复古听音室\n"
           "————————————————\n\n"
           "不是模拟器，是一间被放进窗口里的听音室。\n"
           "卡带仓、FM 刻度、琥珀色 VFD、会呼吸的音箱——\n"
           "用原生 Qt6 / C++ 一笔笔画出。\n\n"
           "城市电台来自公开的 Radio Browser；\n"
           "本地音乐，是您自己的收藏。\n\n"
           "版本  V1.0.0\n"
           "作者  KK-Files\n"
           "联系  QQ 827212416\n"
           "时间  2026.11 · 成都\n\n"
           "愿每一个暂停，都只是为了下一句副歌。"));
}

void MainWindow::dragEnterEvent(QDragEnterEvent *event)
{
    if (event->mimeData()->hasUrls())
        event->acceptProposedAction();
}

void MainWindow::dropEvent(QDropEvent *event)
{
    QStringList files;
    for (const QUrl &url : event->mimeData()->urls()) {
        const QString path = url.toLocalFile();
        if (path.isEmpty())
            continue;
        const QFileInfo info(path);
        if (info.isDir())
            files.append(collectAudioFiles(path));
        else if (isAudioFile(path))
            files.append(info.absoluteFilePath());
    }
    files.removeDuplicates();
    if (!files.isEmpty())
        loadPlaylist(files);
}

QString MainWindow::fmtMs(qint64 ms)
{
    ms = qMax<qint64>(0, ms);
    const qint64 s = ms / 1000;
    return QStringLiteral("%1:%2")
        .arg(s / 60, 2, 10, QLatin1Char('0'))
        .arg(s % 60, 2, 10, QLatin1Char('0'));
}
