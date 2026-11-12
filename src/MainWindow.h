#pragma once

#include "CassetteDeckWidget.h"
#include "RadioBrowser.h"
#include "UiTheme.h"

#include <QMainWindow>
#include <QStringList>
#include <QUrl>
#include <QVector>

class AudioEngine;
class QActionGroup;
class QMenu;

struct RadioStation {
    float freq = 0;
    QString name;
    QString shortLabel;
    QUrl url;
    QString regionId;
};

class MainWindow : public QMainWindow
{
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);
    void loadFile(const QString &path);
    void loadPlaylist(const QStringList &paths, int startIndex = 0);

protected:
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dropEvent(QDropEvent *event) override;

private slots:
    void openFile();
    void openFolder();
    void playNext();
    void playPrev();
    void onTrack(const QString &name);
    void onPosition(qint64 pos);
    void onDuration(qint64 dur);
    void onPlaying(bool playing);
    void onSeekRatio(float ratio);
    void onError(const QString &message);
    void onFrequencyChanged(float mhz);
    void onRadioSeek(int direction);
    void onRadioPower(bool on);
    void onRadioRegionPressed();
    void onRemoteStationsReady(const QString &regionId, const QVector<RemoteStation> &stations);
    void onRemoteFetchFailed(const QString &regionId, const QString &message);
    void onTrackSelected(int index);
    void about();

private:
    void buildMenu();
    void applyTheme(UiTheme::Id id, bool persist = true);
    void rebuildRadioStationMenu();
    void playCurrent();
    void syncDeckPlaylist();
    void loadLyricsForCurrent();
    void initRegions();
    void applyRegion(const QString &regionId, bool autoTune);
    void applyRemoteStations(const QVector<RemoteStation> &remote, bool autoTune);
    void applyFrequency(float mhz, bool autoPlay);
    void enterTapeMode();
    void enterRadioMode();
    void setRadioPower(bool on);
    int nearestStation(float mhz, float *distanceOut = nullptr) const;
    int regionIndex(const QString &regionId) const;
    static QStringList collectAudioFiles(const QString &dirPath);
    static QString fmtMs(qint64 ms);
    static QVector<LyricLine> parseLrcFile(const QString &path);

    AudioEngine *m_engine = nullptr;
    CassetteDeckWidget *m_deck = nullptr;
    RadioBrowser *m_radioBrowser = nullptr;
    qint64 m_duration = 0;
    QStringList m_playlist;
    int m_playlistIndex = -1;
    QVector<RadioRegionDef> m_regions;
    QVector<RadioStation> m_stations;
    QString m_regionId;
    QMenu *m_radioStationMenu = nullptr;
    float m_frequency = 87.5f;
    int m_lockedStation = -1;
    bool m_radioMode = false;
    bool m_radioPower = false;
    bool m_pendingAutoTune = false;
};
