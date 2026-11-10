#pragma once

#include "PaintKit.h"

#include <QWidget>
#include <QHash>
#include <QRectF>
#include <QVector>
#include <QPointF>
#include <QStringList>
#include <QPixmap>

class QTimer;

struct LyricLine {
    qint64 timeMs = 0;
    QString text;
};

class CassetteDeckWidget : public QWidget
{
    Q_OBJECT
public:
    enum class MediaTab { Cover = 0, List = 1, Lyrics = 2, Radio = 3 };
    enum class PlayMode { AllLoop = 0, SingleLoop = 1, Random = 2 };
    enum class VizMode { Wave = 0, Mirror = 1, Bars = 2, Pulse = 3, Dots = 4 };

    explicit CassetteDeckWidget(QWidget *parent = nullptr);

    PlayMode playMode() const { return m_playMode; }

public slots:
    void setLevels(float left, float right);
    void setWaveform(const QVector<float> &samples);
    void setProgress(float ratio);
    void setPlaying(bool playing);
    void setTrackName(const QString &name);
    void setTimeText(const QString &text);
    void setVolume(float value);
    void setMute(bool on);
    void setSourceMode(const QString &mode); // "TAPE" / "FM"
    void setRadioFrequency(float mhz);
    void setRadioStation(const QString &name, bool locked, float signal);
    void setRadioMarkers(const QVector<float> &freqs, const QStringList &labels);
    void setRadioStationNames(const QStringList &names);
    void setRadioPower(bool on);
    bool radioPower() const { return m_radioPower; }
    void setRadioRegionName(const QString &name);
    void setPlaylist(const QStringList &titles, int currentIndex);
    void setPlaylistIndex(int index);
    void setLyrics(const QVector<LyricLine> &lines);
    void setCoverArt(const QPixmap &cover);
    void setMediaTab(MediaTab tab);

signals:
    void openRequested();
    void playPressed();
    void pausePressed();
    void stopPressed();
    void rewindPressed();
    void forwardPressed();
    void seekRequested(float ratio);
    void volumeChanged(float value);
    void sleepFadeChanged(float gain01); // 睡眠渐弱，不改用户音量
    void muteToggled(bool on);
    void megaBassToggled(bool on);
    void loudnessToggled(bool on);
    void dolbyToggled(bool on);
    void toneChanged(float bass, float mid, float treble, float balance);
    void sleepFinished();                 // 定时到：应停止播放
    void sleepRemainingChanged(int sec);  // 剩余秒数（含渐弱提示）
    void frequencyChanged(float mhz);
    void radioSeekRequested(int direction);
    void radioPowerToggled(bool on);
    void radioRegionPressed();
    void trackSelected(int index);
    void radioStationSelected(int index);
    void playModeChanged(PlayMode mode);

protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void leaveEvent(QEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;

private:
    void tick();
    void updateBands();
    void drawRack(QPainter &p, const QRectF &r);
    void drawSpeaker(QPainter &p, const QRectF &rect, float level, bool mirror);
    enum class DriverKind { Tweeter, Mid, Woofer };
    void drawDriverWell(QPainter &p, const QPointF &c, qreal outerR);
    void drawDriver(QPainter &p, const QPointF &c, qreal radius, float level, DriverKind kind);
    void drawBassPort(QPainter &p, const QRectF &rect);
    void drawVizStrip(QPainter &p, const QRectF &ribbon, float level);
    void cycleVizMode();
    QString vizModeLabel() const;
    void drawStack(QPainter &p, const QRectF &stack);
    void drawDisplayModule(QPainter &p, const QRectF &rect);
    void drawVfd(QPainter &p, const QRectF &rect);
    void drawAmpModule(QPainter &p, const QRectF &rect);
    void drawVerticalFader(QPainter &p, const QRectF &track, float value,
                           const QString &label, const QString &key, bool bipolar = false);
    void drawRadioModule(QPainter &p, const QRectF &rect);
    void drawRadioPowerSwitch(QPainter &p, const QRectF &rect);
    void drawTapeModule(QPainter &p, const QRectF &rect);
    void drawHiFiCassette(QPainter &p, const QRectF &rect, bool hasTape, bool playing);
    void drawDeckTransport(QPainter &p, const QRectF &rect, bool hasTape, bool playing);
    void drawMediaPanel(QPainter &p, const QRectF &rect);
    void drawCoverPage(QPainter &p, const QRectF &rect);
    void drawListPage(QPainter &p, const QRectF &rect);
    void drawLyricsPage(QPainter &p, const QRectF &rect);
    void drawRadioPage(QPainter &p, const QRectF &rect);
    QPixmap makeProceduralCover(const QString &title) const;
    void drawReel(QPainter &p, const QPointF &c, qreal rad, float angle, float fill);
    void drawTransportModule(QPainter &p, const QRectF &rect);
    void moduleSeam(QPainter &p, qreal y, const QRectF &stack);
    void flatKey(QPainter &p, const QRectF &rect, const QString &title,
                 const QString &key, bool lit = false, bool hasLed = false);
    void transportKey(QPainter &p, const QRectF &rect, PaintKit::TransportIcon icon,
                      const QString &key, bool lit = false, bool enabled = true);
    bool hasTapeLoaded() const;
    QString hitTest(const QPointF &pos) const;
    void setVolumeFromPos(const QPointF &pos);
    void setSliderFromPos(const QString &key, const QPointF &pos);
    void emitTone();
    void cycleSleepTimer();
    void onSleepTick();
    QString sleepStatusText() const;
    QString playModeLabel(PlayMode mode) const;
    void setFrequencyFromPos(const QPointF &pos);
    float clampFrequency(float mhz) const;
    float freqFromDialX(qreal x) const;
    qreal dialXFromFreq(float mhz) const;
    int currentLyricIndex() const;

    float m_left = 0;
    float m_right = 0;
    QVector<float> m_wave;
    QVector<float> m_bands;
    QVector<float> m_peaks;
    VizMode m_vizMode = VizMode::Wave;
    float m_vizPulse = 0.f;
    float m_progress = 0;
    bool m_playing = false;
    QString m_trackName = QStringLiteral("NO TAPE");
    QString m_timeText = QStringLiteral("00:00");
    QString m_durationText = QStringLiteral("00:00");
    float m_reelAngle = 0;
    float m_volume = 0.75f;
    float m_micLevel = 0.40f;
    float m_echoLevel = 0.28f;
    float m_bass = 0.55f;
    float m_mid = 0.50f;
    float m_treble = 0.50f;
    float m_balance = 0.50f;
    bool m_megaBass = false;
    bool m_loudness = false;
    bool m_dolby = false;
    bool m_mute = false;
    bool m_surround = false;
    int m_sleepPresetMin = 0;   // 0=关, 15/30/60/90
    int m_sleepRemainSec = 0;
    QTimer *m_sleepTimer = nullptr;
    QString m_preset = QStringLiteral("DISCO");
    PlayMode m_playMode = PlayMode::AllLoop;
    QString m_sourceMode = QStringLiteral("TAPE");
    QHash<QString, QRectF> m_sliderTracks;

    // FM tuner
    float m_frequency = 87.5f;
    QString m_radioName;
    bool m_radioPower = false;
    bool m_radioLocked = false;
    float m_radioSignal = 0.f;
    QString m_radioRegionName = QStringLiteral("环球");
    QVector<float> m_radioMarkers;
    QStringList m_radioLabels;
    QStringList m_radioStationNames;
    int m_radioScroll = 0;
    QRectF m_radioViewport;
    QRectF m_dialRect;
    float m_fmMin = 87.5f;
    float m_fmMax = 108.0f;

    // Media panel (right side)
    MediaTab m_mediaTab = MediaTab::Cover;
    QStringList m_playlistTitles;
    int m_playlistIndex = -1;
    int m_listScroll = 0;
    QVector<LyricLine> m_lyrics;
    QPixmap m_coverArt;
    QRectF m_listViewport;
    QRectF m_lyricsViewport;

    QString m_hover;
    QString m_pressed;
    bool m_dragVol = false;
    QString m_dragSlider;
    bool m_dragTune = false;
    bool m_dragTuneKnob = false;
    QHash<QString, QRectF> m_hit;
    QPointF m_knobCenter;
    QPointF m_tuneKnobCenter;
    QRectF m_progressRect;
};
