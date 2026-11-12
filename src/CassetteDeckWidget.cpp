#include "CassetteDeckWidget.h"
#include "PaintKit.h"

#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QLinearGradient>
#include <QRadialGradient>
#include <QConicalGradient>
#include <QFontMetrics>
#include <QTimer>
#include <QtMath>
#include <cmath>
#include <limits>

CassetteDeckWidget::CassetteDeckWidget(QWidget *parent)
    : QWidget(parent)
{
    setMinimumSize(960, 640);
    setMouseTracking(true);
    m_bands = QVector<float>(20, 0.05f);
    m_peaks = QVector<float>(20, 0.f);

    auto *anim = new QTimer(this);
    anim->setInterval(16);
    connect(anim, &QTimer::timeout, this, &CassetteDeckWidget::tick);
    anim->start();

    m_sleepTimer = new QTimer(this);
    m_sleepTimer->setInterval(1000);
    connect(m_sleepTimer, &QTimer::timeout, this, &CassetteDeckWidget::onSleepTick);
}

void CassetteDeckWidget::setTheme(const UiTheme &theme)
{
    m_theme = theme;
    update();
}

void CassetteDeckWidget::setLevels(float left, float right)
{
    // 不在这里 update()：由 tick() 统一刷新，避免播放时全窗重绘把解码拖死
    m_left = PaintKit::clamp01(left);
    m_right = PaintKit::clamp01(right);
    updateBands();
}

void CassetteDeckWidget::setWaveform(const QVector<float> &samples)
{
    m_wave = samples;
    updateBands();
}

void CassetteDeckWidget::setProgress(float ratio)
{
    m_progress = PaintKit::clamp01(ratio);
    // 进度由 tick 刷新；此处不 update，避免高频全窗重绘
}

void CassetteDeckWidget::setPlaying(bool playing)
{
    m_playing = playing;
    update();
}

void CassetteDeckWidget::setTrackName(const QString &name)
{
    m_trackName = name.isEmpty() ? QStringLiteral("NO TAPE") : name.toUpper();
    update();
}

void CassetteDeckWidget::setTimeText(const QString &text)
{
    // Only split "mm:ss / mm:ss" — do not treat track titles with '/' as time
    const int sep = text.indexOf(QStringLiteral(" / "));
    QString nextTime = text.trimmed();
    QString nextDur = m_durationText;
    if (sep > 0) {
        nextTime = text.left(sep).trimmed();
        nextDur = text.mid(sep + 3).trimmed();
    }
    if (nextTime == m_timeText && nextDur == m_durationText)
        return;
    m_timeText = nextTime;
    m_durationText = nextDur;
    // 时长从 00:00 变为真实值时必须立刻刷新，否则看起来像“没加载”
    if (!m_playing)
        update();
}

void CassetteDeckWidget::setVolume(float value)
{
    m_volume = PaintKit::clamp01(value);
    update();
}

void CassetteDeckWidget::setMute(bool on)
{
    if (m_mute == on)
        return;
    m_mute = on;
    update();
}

void CassetteDeckWidget::setSourceMode(const QString &mode)
{
    m_sourceMode = mode;
    update();
}

void CassetteDeckWidget::setRadioFrequency(float mhz)
{
    m_frequency = clampFrequency(mhz);
    update();
}

void CassetteDeckWidget::setRadioStation(const QString &name, bool locked, float signal)
{
    m_radioName = name;
    m_radioLocked = locked;
    m_radioSignal = PaintKit::clamp01(signal);
    update();
}

void CassetteDeckWidget::setRadioMarkers(const QVector<float> &freqs, const QStringList &labels)
{
    m_radioMarkers = freqs;
    m_radioLabels = labels;
    m_radioScroll = 0;
    update();
}

void CassetteDeckWidget::setRadioStationNames(const QStringList &names)
{
    m_radioStationNames = names;
    m_radioScroll = 0;
    update();
}

void CassetteDeckWidget::setRadioPower(bool on)
{
    if (m_radioPower == on)
        return;
    m_radioPower = on;
    update();
}

void CassetteDeckWidget::setRadioRegionName(const QString &name)
{
    if (m_radioRegionName == name)
        return;
    m_radioRegionName = name;
    update();
}

void CassetteDeckWidget::setPlaylist(const QStringList &titles, int currentIndex)
{
    m_playlistTitles = titles;
    m_playlistIndex = currentIndex;
    m_listScroll = 0;
    if (m_coverArt.isNull() && currentIndex >= 0 && currentIndex < titles.size())
        m_coverArt = makeProceduralCover(titles[currentIndex]);
    update();
}

void CassetteDeckWidget::setPlaylistIndex(int index)
{
    m_playlistIndex = index;
    if (index >= 0 && index < m_playlistTitles.size() && m_coverArt.isNull())
        m_coverArt = makeProceduralCover(m_playlistTitles[index]);
    // Keep current track visible in list
    if (index >= 0)
        m_listScroll = qMax(0, index - 3);
    update();
}

void CassetteDeckWidget::setLyrics(const QVector<LyricLine> &lines)
{
    m_lyrics = lines;
    update();
}

void CassetteDeckWidget::setCoverArt(const QPixmap &cover)
{
    m_coverArt = cover;
    update();
}

void CassetteDeckWidget::setMediaTab(MediaTab tab)
{
    m_mediaTab = tab;
    update();
}

float CassetteDeckWidget::clampFrequency(float mhz) const
{
    return qBound(m_fmMin, mhz, m_fmMax);
}

float CassetteDeckWidget::freqFromDialX(qreal x) const
{
    if (m_dialRect.width() <= 1)
        return m_frequency;
    const float t = PaintKit::clamp01(float((x - m_dialRect.left()) / m_dialRect.width()));
    return m_fmMin + t * (m_fmMax - m_fmMin);
}

qreal CassetteDeckWidget::dialXFromFreq(float mhz) const
{
    const float t = (clampFrequency(mhz) - m_fmMin) / (m_fmMax - m_fmMin);
    return m_dialRect.left() + t * m_dialRect.width();
}

void CassetteDeckWidget::updateBands()
{
    // 频谱柱：保留动态余量，避免“全黄顶满”而听感并不饱满
    const int n = m_bands.size();
    const float energy = qMax(m_left, m_right);
    for (int i = 0; i < n; ++i) {
        const float t = float(i) / float(qMax(1, n - 1));
        float w = 0.f;
        if (!m_wave.isEmpty()) {
            const int idx = int(t * (m_wave.size() - 1));
            w = qAbs(m_wave[idx]);
        }
        // 中高频自然衰减，低频略强 —— 更像真实频谱
        const float rollOff = 1.f - 0.55f * t;
        const float bassShape = qExp(-((t - 0.10f) * (t - 0.10f)) / 0.07f);
        const float midShape = qExp(-((t - 0.45f) * (t - 0.45f)) / 0.12f);
        const float trebleShape = qExp(-((t - 0.82f) * (t - 0.82f)) / 0.08f);
        float bassW = 0.25f + 0.35f * m_bass;
        float midW = 0.20f + 0.30f * m_mid;
        float trebleW = 0.15f + 0.25f * m_treble;
        if (m_megaBass)
            bassW *= 1.25f;
        if (m_dynBoost) {
            bassW *= 1.12f;
            midW *= 1.08f;
        }
        if (m_dolby)
            trebleW *= 0.72f; // 杜比降噪：压一点毛刺高频

        float target = w * 0.85f * rollOff
            + energy * (midW * midShape + bassW * bassShape + trebleW * trebleShape);
        // 软压缩：越接近满幅越难再往上顶
        target = PaintKit::clamp01(target);
        target = target / (1.f + 1.2f * target);

        const float cur = m_bands[i];
        // 上升慢、下落快一点，柱子会呼吸而不是贴顶
        m_bands[i] = target > cur ? cur * 0.72f + target * 0.28f : cur * 0.82f;
        m_peaks[i] = qMax(m_peaks[i] * 0.978f, m_bands[i]);
    }
}

void CassetteDeckWidget::tick()
{
    bool need = false;
    const float energy = qMax(m_left, m_right);
    m_vizPulse = energy > m_vizPulse ? energy : m_vizPulse * 0.90f;
    if (m_playing) {
        m_reelAngle = std::fmod(m_reelAngle + 2.4f + 9.f * energy, 360.f);
        need = true;
    }
    if (m_vizMode == VizMode::Pulse && m_vizPulse > 0.02f)
        need = true;
    for (float b : m_bands) {
        if (b > 0.02f) {
            need = true;
            break;
        }
    }
    if (need)
        update();
}

void CassetteDeckWidget::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::TextAntialiasing, true);
    p.setRenderHint(QPainter::SmoothPixmapTransform, true);
    m_hit.clear();

    QLinearGradient bg(0, 0, 0, height());
    bg.setColorAt(0.0, m_theme.rackMid.lighter(115));
    bg.setColorAt(1.0, m_theme.windowBg);
    p.fillRect(rect(), bg);

    // Fill the window edge-to-edge — no letterbox margins
    const QRectF r = QRectF(rect()).adjusted(4, 4, -4, -4);
    drawRack(p, r);

    // 书架箱立柱：略收窄，避免全屏时主低音单元按宽度膨胀得过大
    const qreal spW = r.width() * 0.158;
    const qreal gap = 5;
    const QRectF left(r.left() + 4, r.top() + 5, spW, r.height() - 10);
    const QRectF right(r.right() - 4 - spW, r.top() + 5, spW, r.height() - 10);
    const QRectF stack(left.right() + gap, r.top() + 5,
                       right.left() - left.right() - gap * 2, r.height() - 10);

    // BALANCE 影响左右音箱显示电平
    const float bal = m_balance;
    const float leftGain = PaintKit::clamp01(1.15f - bal * 0.9f) * (m_mute ? 0.f : 1.f);
    const float rightGain = PaintKit::clamp01(0.25f + bal * 0.9f) * (m_mute ? 0.f : 1.f);
    drawSpeaker(p, left, m_left * leftGain, false);
    drawSpeaker(p, right, m_right * rightGain, true);
    drawStack(p, stack);
}

void CassetteDeckWidget::drawRack(QPainter &p, const QRectF &r)
{
    QPainterPath path;
    path.addRoundedRect(r, 6, 6);
    QLinearGradient shell(r.topLeft(), r.bottomLeft());
    shell.setColorAt(0.0, m_theme.rackTop);
    shell.setColorAt(0.04, m_theme.rackMid);
    shell.setColorAt(0.96, m_theme.rackMid.darker(120));
    shell.setColorAt(1.0, m_theme.rackBot);
    p.fillPath(path, shell);

    // 机壳侧向金属高光，增强厚度感
    QLinearGradient gloss(r.topLeft(), r.topRight());
    gloss.setColorAt(0.0, QColor(255, 255, 255, 28));
    gloss.setColorAt(0.08, QColor(255, 255, 255, 0));
    gloss.setColorAt(0.92, QColor(255, 255, 255, 0));
    gloss.setColorAt(1.0, QColor(255, 255, 255, 18));
    p.fillPath(path, gloss);

    p.setPen(QPen(m_theme.rackEdge, 1.1));
    p.drawRoundedRect(r.adjusted(0.5, 0.5, -0.5, -0.5), 6, 6);
    p.setPen(QPen(QColor(0, 0, 0, 190), 2.2));
    p.drawRoundedRect(r.adjusted(2.5, 2.5, -2.5, -2.5), 5, 5);

    // 顶部细装饰线
    p.setPen(QPen(QColor(m_theme.accent.red(), m_theme.accent.green(), m_theme.accent.blue(), 90), 1.0));
    p.drawLine(QPointF(r.left() + 18, r.top() + 3.5), QPointF(r.right() - 18, r.top() + 3.5));

    p.setOpacity(0.32);
    p.drawPixmap(r.toRect(), PaintKit::plasticNoise(int(r.width()), int(r.height()), 11, 9));
    p.setOpacity(0.14);
    p.drawPixmap(r.toRect(), PaintKit::brushedMetal(int(r.width()), int(r.height()), 5));
    p.setOpacity(1.0);
}

void CassetteDeckWidget::drawSpeaker(QPainter &p, const QRectF &rect, float level, bool mirror)
{
    // === Cabinet body with rounded vertical edges (bookshelf speaker) ===
    QPainterPath cabinet;
    cabinet.addRoundedRect(rect, 10, 10);

    // Drop shadow under / beside enclosure
    p.setPen(Qt::NoPen);
    p.setBrush(QColor(0, 0, 0, 100));
    p.drawRoundedRect(rect.adjusted(3, 5, 3, 5), 10, 10);

    QLinearGradient body(rect.topLeft(), rect.topRight());
    if (mirror) {
        body.setColorAt(0.0, m_theme.rackBot);
        body.setColorAt(0.16, m_theme.chassisMid);
        body.setColorAt(0.55, m_theme.chassisLo);
        body.setColorAt(1.0, m_theme.chassisHi);
    } else {
        body.setColorAt(0.0, m_theme.chassisHi);
        body.setColorAt(0.45, m_theme.chassisLo);
        body.setColorAt(0.84, m_theme.chassisMid);
        body.setColorAt(1.0, m_theme.rackBot);
    }
    p.fillPath(cabinet, body);

    // Top/bottom bevel strips
    QLinearGradient topBevel(rect.topLeft(), QPointF(rect.left(), rect.top() + 16));
    topBevel.setColorAt(0.0, QColor(80, 80, 86, 170));
    topBevel.setColorAt(1.0, QColor(0, 0, 0, 0));
    p.fillPath(cabinet, topBevel);
    QLinearGradient botBevel(QPointF(rect.left(), rect.bottom() - 18), rect.bottomLeft());
    botBevel.setColorAt(0.0, QColor(0, 0, 0, 0));
    botBevel.setColorAt(1.0, QColor(0, 0, 0, 90));
    p.fillPath(cabinet, botBevel);

    p.setOpacity(0.28);
    p.drawPixmap(rect.toRect(), PaintKit::plasticNoise(int(rect.width()), int(rect.height()), 40 + int(mirror), 7));
    p.setOpacity(1.0);

    p.setPen(QPen(QColor(62, 62, 66), 1.2));
    p.setBrush(Qt::NoBrush);
    p.drawRoundedRect(rect.adjusted(0.5, 0.5, -0.5, -0.5), 10, 10);
    p.setPen(QPen(QColor(0, 0, 0, 150), 2));
    p.drawRoundedRect(rect.adjusted(2, 2, -2, -2), 8, 8);

    // Corner mounting screws
    const qreal inset = 10;
    for (const QPointF &pt : {
             QPointF(rect.left() + inset, rect.top() + inset),
             QPointF(rect.right() - inset, rect.top() + inset),
             QPointF(rect.left() + inset, rect.bottom() - inset),
             QPointF(rect.right() - inset, rect.bottom() - inset)})
        PaintKit::drawScrew(p, pt, 2.8);

    // 音箱顶部居中铭牌
    {
        const QRectF plate(rect.left() + 8, rect.top() + 4, rect.width() - 16, 12);
        PaintKit::drawLabel(p, plate.translated(0.7, 0.7), QStringLiteral("拾音盒子"), 8, true,
                            QColor(0, 0, 0, 140), Qt::AlignCenter, 0.6);
        PaintKit::drawLabel(p, plate, QStringLiteral("拾音盒子"), 8, true,
                            m_theme.plateGold, Qt::AlignCenter, 0.6);
    }

    // Front baffle — tighter inset so drivers can fill the face
    const QRectF baffle = rect.adjusted(7, 18, -7, -14);
    PaintKit::fillBeveledRect(p, baffle, m_theme.baffle, 4, 5, false);
    const QRectF face = baffle.adjusted(2, 2, -2, -2);

    QLinearGradient faceG(face.topLeft(), face.bottomLeft());
    faceG.setColorAt(0.0, m_theme.chassisMid);
    faceG.setColorAt(0.45, m_theme.baffle);
    faceG.setColorAt(1.0, m_theme.baffleDeep);
    p.fillRect(face, faceG);

    // Soft side AO on baffle (cylindrical enclosure feel)
    QLinearGradient sideAo(face.topLeft(), face.topRight());
    sideAo.setColorAt(0.0, QColor(0, 0, 0, mirror ? 20 : 80));
    sideAo.setColorAt(0.32, QColor(255, 255, 255, 12));
    sideAo.setColorAt(0.68, QColor(255, 255, 255, 10));
    sideAo.setColorAt(1.0, QColor(0, 0, 0, mirror ? 80 : 20));
    p.fillRect(face, sideAo);

    // 三分频：宽度定径、高度封顶；立面按比例铺开，避免全屏时中段大片留白
    const qreal cx = face.center().x();
    const qreal base = face.width();
    const qreal h = face.height();
    const qreal exc = 1.0 + level * 0.05;

    const qreal twR = qMin(base * 0.112, h * 0.036);
    const qreal midR = qMin(base * 0.155, h * 0.055);
    const qreal wooR = qMin(base * 0.360, h * 0.145);
    const qreal portR = qMin(base * 0.150, h * 0.052);
    // 律动条限高：不再吃掉低音与倒相孔之间的全部空隙
    const qreal ribbonH = qBound(14.0, h * 0.042, 30.0);
    const qreal railH = 2.0;
    const qreal bottomPad = h * 0.022;
    const qreal stackBottom = face.bottom() - bottomPad - portR * 2.05 - 6.0 - ribbonH - 5.0 - railH;

    // 在「顶 → 低音下沿」区间内按比例排布，把中段填满
    const qreal topPad = qMax(twR * 1.25, h * 0.038);
    const qreal y0 = face.top() + topPad;
    const qreal y1 = stackBottom - wooR; // 低音中心上限
    const qreal span = qMax(1.0, y1 - y0);
    QPointF tw(cx - base * (mirror ? -0.11 : 0.11), y0 + span * 0.02);
    QPointF mid(cx + base * (mirror ? -0.09 : 0.09), y0 + span * 0.28);
    QPointF woofer(cx, y0 + span * 0.68);

    // 防止单元互相侵入：按最小中心距微调
    const qreal minTwMid = twR + midR + 5.0;
    const qreal minMidWoo = midR + wooR + 8.0;
    if (mid.y() - tw.y() < minTwMid)
        mid.ry() = tw.y() + minTwMid;
    if (woofer.y() - mid.y() < minMidWoo)
        woofer.ry() = mid.y() + minMidWoo;
    if (woofer.y() > y1)
        woofer.ry() = y1;

    drawDriverWell(p, tw, twR * 1.18);
    drawDriver(p, tw, twR * (1.0 + level * 0.02), level * 0.45f, DriverKind::Tweeter);

    drawDriverWell(p, mid, midR * 1.16);
    drawDriver(p, mid, midR * (1.0 + level * 0.025), level * 0.7f, DriverKind::Mid);

    drawDriverWell(p, woofer, wooR * 1.08);
    drawDriver(p, woofer, wooR * exc, level, DriverKind::Woofer);

    // 装饰条紧贴低音下方
    const qreal railY = qMin(woofer.y() + wooR * 1.10, stackBottom);
    const QRectF rail(face.left() + 10, railY, face.width() - 20, railH);
    QLinearGradient railG(rail.topLeft(), rail.topRight());
    railG.setColorAt(0.0, QColor(90, 70, 40, 40));
    railG.setColorAt(0.5, QColor(210, 170, 90, 200));
    railG.setColorAt(1.0, QColor(90, 70, 40, 40));
    p.fillRect(rail, railG);

    // 律动条固定高度，紧随装饰条；倒相孔贴底
    const QRectF ribbon(face.left() + 10, rail.bottom() + 4,
                        face.width() - 20, ribbonH);
    if (ribbon.height() >= 8) {
        drawVizStrip(p, ribbon, level);
        m_hit[mirror ? QStringLiteral("viz:r") : QStringLiteral("viz:l")] = ribbon;
    }

    const qreal portGap = base * 0.06;
    const qreal portY = face.bottom() - bottomPad - portR;
    drawBassPort(p, QRectF(cx - portGap * 0.5 - portR * 2, portY - portR, portR * 2, portR * 2));
    drawBassPort(p, QRectF(cx + portGap * 0.5, portY - portR, portR * 2, portR * 2));
}

void CassetteDeckWidget::drawVizStrip(QPainter &p, const QRectF &ribbon, float level)
{
    p.setBrush(QColor(5, 7, 6));
    p.setPen(QPen(m_hover.startsWith(QLatin1String("viz:")) ? QColor(80, 70, 40) : QColor(28, 28, 32), 1));
    p.drawRoundedRect(ribbon, 2, 2);

    const QColor glow(m_theme.vizGlow.red(), m_theme.vizGlow.green(), m_theme.vizGlow.blue(),
                      int(40 + level * 80));
    const QColor core(m_theme.vizCore.red(), m_theme.vizCore.green(), m_theme.vizCore.blue(),
                      int(130 + level * 100));
    const qreal midY = ribbon.center().y();
    const qreal amp = ribbon.height() * 0.42 * (0.35 + level);
    const int nWave = m_wave.size();
    const int nBand = m_bands.size();

    auto sampleWave = [&](int i, int n) -> float {
        if (nWave <= 0)
            return level * 0.25f;
        const int idx = int(qreal(i) / qMax(1, n - 1) * (nWave - 1));
        return qAbs(m_wave[qBound(0, idx, nWave - 1)]);
    };

    switch (m_vizMode) {
    case VizMode::Wave: {
        if (nWave <= 0)
            break;
        QPainterPath path;
        for (int i = 0; i < nWave; ++i) {
            const qreal x = ribbon.left() + qreal(i) / qMax(1, nWave - 1) * ribbon.width();
            const qreal y = midY - sampleWave(i, nWave) * amp;
            if (i == 0)
                path.moveTo(x, y);
            else
                path.lineTo(x, y);
        }
        p.setPen(QPen(glow, 2.4));
        p.drawPath(path);
        p.setPen(QPen(core, 1.0));
        p.drawPath(path);
        break;
    }
    case VizMode::Mirror: {
        // 对称示波器：上下镜像填充
        QPainterPath path;
        const int steps = qMax(8, nWave > 0 ? nWave : 32);
        path.moveTo(ribbon.left(), midY);
        for (int i = 0; i < steps; ++i) {
            const qreal x = ribbon.left() + qreal(i) / qMax(1, steps - 1) * ribbon.width();
            path.lineTo(x, midY - sampleWave(i, steps) * amp);
        }
        for (int i = steps - 1; i >= 0; --i) {
            const qreal x = ribbon.left() + qreal(i) / qMax(1, steps - 1) * ribbon.width();
            path.lineTo(x, midY + sampleWave(i, steps) * amp);
        }
        path.closeSubpath();
        QLinearGradient fill(ribbon.topLeft(), ribbon.bottomLeft());
        fill.setColorAt(0.0, QColor(255, 160, 50, 40));
        fill.setColorAt(0.5, QColor(255, 120, 30, int(70 + level * 90)));
        fill.setColorAt(1.0, QColor(255, 160, 50, 40));
        p.setBrush(fill);
        p.setPen(QPen(core, 1.0));
        p.drawPath(path);
        break;
    }
    case VizMode::Bars: {
        // 频谱柱：用分频能量表现节奏
        const int bars = qMin(24, qMax(8, nBand > 0 ? nBand : 16));
        const qreal gap = 1.2;
        const qreal bw = (ribbon.width() - gap * (bars - 1)) / bars;
        for (int i = 0; i < bars; ++i) {
            float v = level * 0.2f;
            if (nBand > 0) {
                const int idx = int(qreal(i) / qMax(1, bars - 1) * (nBand - 1));
                v = m_bands[qBound(0, idx, nBand - 1)];
            } else {
                v = sampleWave(i, bars);
            }
            const qreal h = qMax(1.5, ribbon.height() * 0.12 + v * ribbon.height() * 0.82);
            const QRectF bar(ribbon.left() + i * (bw + gap),
                             ribbon.bottom() - 2 - h, bw, h);
            QLinearGradient g(bar.bottomLeft(), bar.topLeft());
            g.setColorAt(0.0, QColor(180, 70, 20));
            g.setColorAt(0.55, QColor(255, 150, 40));
            g.setColorAt(1.0, QColor(255, 220, 120));
            p.setPen(Qt::NoPen);
            p.setBrush(g);
            p.drawRoundedRect(bar, 1.0, 1.0);
            if (nBand > 0) {
                const int idx = int(qreal(i) / qMax(1, bars - 1) * (nBand - 1));
                const float pk = m_peaks[qBound(0, idx, nBand - 1)];
                const qreal py = ribbon.bottom() - 2 - pk * ribbon.height() * 0.82;
                p.setPen(QPen(QColor(255, 210, 120, 200), 1));
                p.drawLine(QPointF(bar.left(), py), QPointF(bar.right(), py));
            }
        }
        break;
    }
    case VizMode::Pulse: {
        // 节拍脉冲环：随音量扩张
        const float e = qMax(level, m_vizPulse);
        const int rings = 4;
        for (int i = 0; i < rings; ++i) {
            const float t = (i + 1) / float(rings);
            const qreal rx = ribbon.width() * 0.18 * t * (0.55 + e);
            const qreal ry = ribbon.height() * 0.42 * t * (0.55 + e);
            p.setBrush(Qt::NoBrush);
            p.setPen(QPen(QColor(255, 160, 50, int(160 * (1.f - t) + e * 60)), 1.4));
            p.drawEllipse(ribbon.center(), rx, ry);
        }
        p.setBrush(QColor(255, 180, 70, int(80 + e * 140)));
        p.setPen(Qt::NoPen);
        p.drawEllipse(ribbon.center(), 2.5 + e * 3.5, 2.5 + e * 3.5);
        break;
    }
    case VizMode::Dots: {
        // 粒子雨：离散点阵跟随波形
        const int cols = 28;
        const int rows = qMax(3, int(ribbon.height() / 3.5));
        for (int c = 0; c < cols; ++c) {
            const float v = sampleWave(c, cols);
            const int lit = int(v * rows * (0.5f + level));
            for (int r = 0; r < rows; ++r) {
                if (r > lit)
                    continue;
                const qreal x = ribbon.left() + (c + 0.5) / cols * ribbon.width();
                const qreal y = ribbon.bottom() - 2 - (r + 0.5) / rows * (ribbon.height() - 4);
                const float t = float(r) / float(qMax(1, rows - 1));
                p.setPen(Qt::NoPen);
                p.setBrush(QColor(255, int(140 + t * 80), int(40 + t * 40),
                                  int(100 + v * 120)));
                p.drawEllipse(QPointF(x, y), 1.35, 1.35);
            }
        }
        break;
    }
    }

    // 角落模式提示（悬停时）
    if (m_hover.startsWith(QLatin1String("viz:"))) {
        PaintKit::drawLabel(p, QRectF(ribbon.left() + 3, ribbon.top() + 1, ribbon.width() - 6, 9),
                            vizModeLabel(), 5, true, QColor(255, 180, 90, 200),
                            Qt::AlignLeft | Qt::AlignVCenter);
    }
}

void CassetteDeckWidget::cycleVizMode()
{
    const int n = 5;
    m_vizMode = VizMode((int(m_vizMode) + 1) % n);
    update();
}

QString CassetteDeckWidget::vizModeLabel() const
{
    switch (m_vizMode) {
    case VizMode::Mirror: return QStringLiteral("MIRROR");
    case VizMode::Bars:   return QStringLiteral("SPECTRUM");
    case VizMode::Pulse:  return QStringLiteral("PULSE");
    case VizMode::Dots:   return QStringLiteral("DOTS");
    case VizMode::Wave:
    default:              return QStringLiteral("WAVE");
    }
}

void CassetteDeckWidget::drawDriverWell(QPainter &p, const QPointF &c, qreal outerR)
{
    // Soft contact shade under the cutout
    QRadialGradient shade(c + QPointF(0, outerR * 0.08), outerR * 1.15);
    shade.setColorAt(0.55, QColor(0, 0, 0, 0));
    shade.setColorAt(1.0, QColor(0, 0, 0, 55));
    p.setBrush(shade);
    p.setPen(Qt::NoPen);
    p.drawEllipse(c, outerR * 1.06, outerR * 1.06);

    // Deep circular recess cut into baffle
    QRadialGradient pit(c, outerR);
    pit.setColorAt(0.0, QColor(3, 3, 4));
    pit.setColorAt(0.70, QColor(8, 8, 10));
    pit.setColorAt(0.88, QColor(26, 26, 28));
    pit.setColorAt(1.0, QColor(58, 58, 62));
    p.setBrush(pit);
    p.setPen(QPen(QColor(0, 0, 0, 210), 1.3));
    p.drawEllipse(c, outerR, outerR);

    // Machined lip (bright top arc + dark bottom)
    p.setPen(QPen(QColor(120, 120, 126, 110), 1.3));
    p.setBrush(Qt::NoBrush);
    p.drawArc(QRectF(c.x() - outerR + 1, c.y() - outerR + 1, outerR * 2 - 2, outerR * 2 - 2),
              35 * 16, 130 * 16);
    p.setPen(QPen(QColor(0, 0, 0, 100), 1.2));
    p.drawArc(QRectF(c.x() - outerR + 1, c.y() - outerR + 1, outerR * 2 - 2, outerR * 2 - 2),
              210 * 16, 110 * 16);
}

void CassetteDeckWidget::drawDriver(QPainter &p, const QPointF &c, qreal radius, float level, DriverKind kind)
{
    // Contact shadow
    QRadialGradient shadow(c + QPointF(1.4, 2.8), radius * 1.25);
    shadow.setColorAt(0.0, QColor(0, 0, 0, 150));
    shadow.setColorAt(1.0, QColor(0, 0, 0, 0));
    p.setBrush(shadow);
    p.setPen(Qt::NoPen);
    p.drawEllipse(c + QPointF(1.4, 2.4), radius * 1.06, radius * 1.06);

    // Metal basket / frame ring — warmer chrome on woofer
    QRadialGradient rim(c - QPointF(radius * 0.28, radius * 0.32), radius * 1.28);
    if (kind == DriverKind::Woofer) {
        rim.setColorAt(0.0, QColor(130, 128, 122));
        rim.setColorAt(0.28, QColor(72, 70, 66));
        rim.setColorAt(0.70, QColor(28, 28, 30));
        rim.setColorAt(1.0, QColor(6, 6, 8));
    } else {
        rim.setColorAt(0.0, QColor(110, 110, 116));
        rim.setColorAt(0.35, QColor(52, 52, 56));
        rim.setColorAt(0.75, QColor(22, 22, 24));
        rim.setColorAt(1.0, QColor(8, 8, 10));
    }
    p.setBrush(rim);
    p.setPen(QPen(QColor(140, 140, 146), kind == DriverKind::Woofer ? 1.4 : 1.0));
    p.drawEllipse(c, radius, radius);

    // Thin bright edge ring
    p.setPen(QPen(QColor(200, 200, 205, kind == DriverKind::Woofer ? 70 : 45), 0.9));
    p.setBrush(Qt::NoBrush);
    p.drawEllipse(c, radius * 0.985, radius * 0.985);

    // Rubber surround (thick for woofer)
    const qreal surroundR = radius * (kind == DriverKind::Woofer ? 0.91 : 0.86);
    QRadialGradient sur(c, surroundR);
    sur.setColorAt(0.00, QColor(24, 24, 26));
    sur.setColorAt(0.55, QColor(14, 14, 16));
    sur.setColorAt(0.74, QColor(48, 48, 52));
    sur.setColorAt(0.86, QColor(16, 16, 18));
    sur.setColorAt(1.00, QColor(40, 40, 44));
    p.setBrush(sur);
    p.setPen(Qt::NoPen);
    p.drawEllipse(c, surroundR, surroundR);

    // Surround ridge lines
    const int surRings = kind == DriverKind::Woofer ? 4 : 2;
    for (int i = 0; i < surRings; ++i) {
        const qreal t = 0.88 + 0.08 * i / qMax(1, surRings - 1);
        p.setPen(QPen(QColor(0, 0, 0, 55), 0.7));
        p.drawEllipse(c, surroundR * t, surroundR * t);
        p.setPen(QPen(QColor(80, 80, 84, 40), 0.6));
        p.drawEllipse(c, surroundR * (t - 0.015), surroundR * (t - 0.015));
    }

    // Cone dish — offset gradient = parabolic 3D cue
    const qreal coneR = radius * (0.66 + level * 0.04);
    const QPointF light = c - QPointF(coneR * 0.30, coneR * 0.34);
    QRadialGradient cone(light, coneR * 1.18);
    if (kind == DriverKind::Tweeter) {
        cone.setColorAt(0.0, QColor(245, 242, 235));
        cone.setColorAt(0.22, QColor(190, 185, 175));
        cone.setColorAt(0.60, QColor(115, 110, 100));
        cone.setColorAt(1.0, QColor(50, 48, 44));
    } else if (kind == DriverKind::Mid) {
        cone.setColorAt(0.0, QColor(78, 78, 82));
        cone.setColorAt(0.32, QColor(38, 38, 42));
        cone.setColorAt(0.72, QColor(14, 14, 16));
        cone.setColorAt(1.0, QColor(4, 4, 6));
    } else {
        cone.setColorAt(0.0, QColor(68, 66, 62));
        cone.setColorAt(0.18, QColor(36, 34, 32));
        cone.setColorAt(0.48, QColor(18, 18, 20));
        cone.setColorAt(0.82, QColor(7, 7, 8));
        cone.setColorAt(1.0, QColor(1, 1, 2));
    }
    p.setBrush(cone);
    p.setPen(Qt::NoPen);
    p.drawEllipse(c, coneR, coneR);

    // Concentric cone corrugations
    const int rings = (kind == DriverKind::Tweeter) ? 3 : (kind == DriverKind::Mid ? 6 : 10);
    for (int i = 1; i <= rings; ++i) {
        const qreal rr = coneR * (0.18 + 0.78 * i / (rings + 0.4));
        p.setPen(QPen(QColor(255, 255, 255, kind == DriverKind::Tweeter ? 32 : 12), 0.65));
        p.drawEllipse(c, rr, rr);
        p.setPen(QPen(QColor(0, 0, 0, 40), 0.65));
        p.drawEllipse(c + QPointF(0.45, 0.45), rr, rr);
    }

    // Specular streak across cone
    QPainterPath gloss;
    gloss.addEllipse(c - QPointF(coneR * 0.38, coneR * 0.42), coneR * 0.58, coneR * 0.34);
    QRadialGradient glossG(c - QPointF(coneR * 0.38, coneR * 0.48), coneR * 0.52);
    glossG.setColorAt(0.0, QColor(255, 255, 255, kind == DriverKind::Tweeter ? 85 : 42));
    glossG.setColorAt(1.0, QColor(255, 255, 255, 0));
    p.setBrush(glossG);
    p.setPen(Qt::NoPen);
    p.drawPath(gloss);

    // Dust cap / phase plug
    const qreal capR = coneR * (kind == DriverKind::Tweeter ? 0.34 : (kind == DriverKind::Mid ? 0.22 : 0.18))
                       * (1.0 + level * 0.14);
    QRadialGradient cap(c - QPointF(capR * 0.35, capR * 0.4), capR * 1.35);
    if (kind == DriverKind::Tweeter) {
        cap.setColorAt(0.0, QColor(255, 255, 255));
        cap.setColorAt(0.22, QColor(220, 220, 225));
        cap.setColorAt(0.55, QColor(130, 130, 138));
        cap.setColorAt(1.0, QColor(45, 45, 50));
    } else {
        const int glow = int(55 + level * 150);
        cap.setColorAt(0.0, QColor(230, 200, 140, glow));
        cap.setColorAt(0.35, QColor(120, 90, 50, int(glow * 0.65)));
        cap.setColorAt(1.0, QColor(18, 16, 12, 50));
    }
    p.setBrush(cap);
    p.drawEllipse(c, capR, capR);
    if (kind == DriverKind::Tweeter) {
        p.setPen(QPen(QColor(255, 255, 255, 170), 1.1));
        p.drawLine(c + QPointF(-capR * 0.55, 0), c + QPointF(capR * 0.55, 0));
        p.drawLine(c + QPointF(0, -capR * 0.55), c + QPointF(0, capR * 0.55));
    }

    // Audio-reactive rim glow
    if (level > 0.03f) {
        p.setPen(QPen(QColor(255, 150, 50, int(20 + level * 110)), kind == DriverKind::Woofer ? 2.2 : 1.6));
        p.setBrush(Qt::NoBrush);
        p.drawEllipse(c, radius * (1.01 + level * 0.03), radius * (1.01 + level * 0.03));
    }
}

void CassetteDeckWidget::drawBassPort(QPainter &p, const QRectF &rect)
{
    // Soft outer shade
    QRadialGradient shade(rect.center() + QPointF(0, rect.height() * 0.06), rect.width() * 0.62);
    shade.setColorAt(0.7, QColor(0, 0, 0, 0));
    shade.setColorAt(1.0, QColor(0, 0, 0, 60));
    p.setBrush(shade);
    p.setPen(Qt::NoPen);
    p.drawEllipse(rect.adjusted(-2, -1, 2, 3));

    // Outer flared ring
    QRadialGradient ring(rect.center() - QPointF(rect.width() * 0.14, rect.height() * 0.18),
                         rect.width() * 0.58);
    ring.setColorAt(0.0, QColor(72, 72, 76));
    ring.setColorAt(0.40, QColor(36, 36, 40));
    ring.setColorAt(0.78, QColor(14, 14, 16));
    ring.setColorAt(1.0, QColor(6, 6, 8));
    p.setBrush(ring);
    p.setPen(QPen(QColor(90, 90, 94), 1.1));
    p.drawEllipse(rect);

    // Flare lip
    p.setPen(QPen(QColor(150, 150, 155, 70), 1.2));
    p.setBrush(Qt::NoBrush);
    p.drawArc(rect.adjusted(1.5, 1.5, -1.5, -1.5), 45 * 16, 110 * 16);

    // Deep tunnel
    const QRectF hole = rect.adjusted(rect.width() * 0.17, rect.height() * 0.17,
                                      -rect.width() * 0.17, -rect.height() * 0.17);
    QRadialGradient tunnel(hole.center() + QPointF(0, hole.height() * 0.1), hole.width() * 0.58);
    tunnel.setColorAt(0.0, QColor(0, 0, 0));
    tunnel.setColorAt(0.50, QColor(4, 4, 6));
    tunnel.setColorAt(0.82, QColor(16, 16, 18));
    tunnel.setColorAt(1.0, QColor(42, 42, 46));
    p.setBrush(tunnel);
    p.setPen(QPen(QColor(0, 0, 0), 1.3));
    p.drawEllipse(hole);

    // Inner specular on port lip
    p.setPen(QPen(QColor(140, 140, 145, 100), 1.3));
    p.setBrush(Qt::NoBrush);
    p.drawArc(rect.adjusted(2.5, 2.5, -2.5, -2.5), 50 * 16, 100 * 16);
}

void CassetteDeckWidget::drawStack(QPainter &p, const QRectF &stack)
{
    PaintKit::fillBeveledRect(p, stack, m_theme.chassisLo, 2, 3, true);
    p.setOpacity(0.28);
    p.drawPixmap(stack.toRect(), PaintKit::plasticNoise(int(stack.width()), int(stack.height()), 21, 7));
    p.setOpacity(1.0);

    const qreal h = stack.height();
    const qreal y0 = stack.top();
    const qreal y5 = stack.bottom();
    // Adaptive stack: VFD/amp/radio need readable room; never starve the tape bay
    const qreal cdH = qBound(26.0, h * 0.055, 44.0);
    const qreal y4 = y5 - cdH;
    const qreal tapeMin = qBound(120.0, h * 0.28, 220.0);
    qreal dispH = qBound(92.0, h * 0.15, 140.0);      // VFD 3-line readout
    qreal ampH = qBound(148.0, h * 0.24, 204.0);     // amp: 预设 + 数字读数 + 扩展开关
    qreal radioH = qBound(96.0, h * 0.16, 140.0);
    qreal y1 = y0 + dispH;
    qreal y2 = y1 + ampH;
    qreal y3 = y2 + radioH;
    if (y3 > y4 - tapeMin) {
        // Compress upper modules proportionally so cassette still has breathing room
        const qreal budget = qMax(200.0, (y4 - tapeMin) - y0);
        const qreal scale = budget / (dispH + ampH + radioH);
        dispH *= scale;
        ampH *= scale;
        radioH *= scale;
        y1 = y0 + dispH;
        y2 = y1 + ampH;
        y3 = y2 + radioH;
    }

    drawDisplayModule(p, QRectF(stack.left() + 1, y0, stack.width() - 2, y1 - y0));
    moduleSeam(p, y1, stack);
    drawAmpModule(p, QRectF(stack.left() + 1, y1, stack.width() - 2, y2 - y1));
    moduleSeam(p, y2, stack);
    drawRadioModule(p, QRectF(stack.left() + 1, y2, stack.width() - 2, y3 - y2));
    moduleSeam(p, y3, stack);
    drawTapeModule(p, QRectF(stack.left() + 1, y3, stack.width() - 2, y4 - y3));
    moduleSeam(p, y4, stack);
    drawTransportModule(p, QRectF(stack.left() + 1, y4, stack.width() - 2, y5 - y4));
}

void CassetteDeckWidget::moduleSeam(QPainter &p, qreal y, const QRectF &stack)
{
    p.setPen(QPen(QColor(0, 0, 0), 3));
    p.drawLine(QPointF(stack.left() + 4, y), QPointF(stack.right() - 4, y));
    p.setPen(QPen(QColor(55, 55, 60), 1));
    p.drawLine(QPointF(stack.left() + 4, y + 2), QPointF(stack.right() - 4, y + 2));
    PaintKit::drawScrew(p, QPointF(stack.left() + 12, y + 1), 2.2);
    PaintKit::drawScrew(p, QPointF(stack.right() - 12, y + 1), 2.2);
}

void CassetteDeckWidget::drawDisplayModule(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);
    const QRectF face = rect.adjusted(6, 3, -6, -3);
    PaintKit::fillBeveledRect(p, face, QColor(30, 30, 34), 2, 3, true);

    const qreal headerH = qBound(18.0, face.height() * 0.22, 26.0);
    PaintKit::drawLabel(p, QRectF(face.left() + 10, face.top() + 2, 120, headerH - 4),
                        QStringLiteral("DISPLAY"), 9, true, QColor(200, 200, 204),
                        Qt::AlignLeft | Qt::AlignVCenter, 1.6);
    if (face.width() > 420) {
        PaintKit::drawLabel(p, QRectF(face.left() + 120, face.top() + 3, 180, headerH - 6),
                            QStringLiteral("复古听音室"),
                            8, false, QColor(130, 130, 134), Qt::AlignLeft | Qt::AlignVCenter);
    }

    const qreal keyH = qMin(16.0, headerH - 2);
    flatKey(p, QRectF(face.right() - 108, face.top() + 2, 46, keyH), QStringLiteral("OPEN"), QStringLiteral("open"));
    flatKey(p, QRectF(face.right() - 56, face.top() + 2, 46, keyH), QStringLiteral("POWER"),
            QStringLiteral("power"), m_playing, true);

    const QRectF vfdOuter(face.left() + 10, face.top() + headerH,
                          face.width() - 20, face.bottom() - (face.top() + headerH) - 4);
    if (vfdOuter.height() > 20) {
        const QRectF pit = PaintKit::drawRecessedWell(p, vfdOuter, 3);
        drawVfd(p, pit.adjusted(3, 2, -3, -2));
    }
    p.restore();
}

void CassetteDeckWidget::drawVfd(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);
    QLinearGradient g(rect.topLeft(), rect.bottomLeft());
    g.setColorAt(0.0, QColor(10, 18, 12));
    g.setColorAt(0.5, QColor(4, 8, 5));
    g.setColorAt(1.0, QColor(8, 14, 10));
    p.fillRect(rect, g);

    QRadialGradient wash(rect.center(), rect.width() * 0.55);
    wash.setColorAt(0.0, QColor(255, 110, 20, 30));
    wash.setColorAt(1.0, QColor(0, 0, 0, 0));
    p.fillRect(rect, wash);

    const QRectF bars(rect.left() + 8, rect.top() + 4, rect.width() * 0.48, rect.height() - 8);
    const int n = m_bands.size();
    const qreal gap = 1.6;
    const qreal bw = (bars.width() - gap * (n - 1)) / n;
    const int segs = 14;
    for (int i = 0; i < n; ++i) {
        const qreal x = bars.left() + i * (bw + gap);
        const int lit = int(m_bands[i] * segs);
        const int peak = int(m_peaks[i] * segs);
        for (int s = 0; s < segs; ++s) {
            const qreal y = bars.bottom() - (s + 1) * (bars.height() / segs);
            const QRectF seg(x, y + 0.6, bw, bars.height() / segs - 1.4);
            const float t = float(s) / float(qMax(1, segs - 1));
            QColor c;
            if (s < lit) {
                c = QColor(255, int(170 - t * 90), int(40 - t * 25));
                if (s >= int(segs * 0.78))
                    c = QColor(255, int(70 + (1 - t) * 40), 20);
            } else if (s == peak && peak > 0) {
                c = QColor(255, 90, 30, 200);
            } else {
                c = QColor(55, 28, 8, 160);
            }
            p.setPen(Qt::NoPen);
            p.setBrush(c);
            p.drawRect(seg);
        }
    }

    const QRectF info(bars.right() + 10, rect.top() + 2, rect.right() - bars.right() - 12, rect.height() - 4);
    const QColor glow(255, 150, 45);
    const bool fm = m_sourceMode == QLatin1String("FM");

    auto fitFonts = [&](int statusPt, int mainPt, int subPt, int rows, qreal barH, qreal gapY,
                        QFont &fStatus, QFont &fMain, QFont &fSub, qreal &h1, qreal &h2, qreal &h3, qreal &totalH) {
        for (int guard = 0; guard < 8; ++guard) {
            fStatus = QFont(QStringLiteral("Consolas"), statusPt, QFont::Bold);
            fMain = QFont(QStringLiteral("Consolas"), mainPt, QFont::Bold);
            fSub = QFont(QStringLiteral("Consolas"), subPt);
            h1 = QFontMetrics(fStatus).height();
            h2 = QFontMetrics(fMain).height();
            h3 = QFontMetrics(fSub).height();
            totalH = h1 + h2 + h3 + gapY * (rows - 1) + barH;
            if (totalH <= info.height() || (statusPt <= 6 && mainPt <= 9 && subPt <= 6))
                break;
            if (mainPt > 9) --mainPt;
            else if (statusPt > 6) --statusPt;
            else if (subPt > 6) --subPt;
            else break;
        }
    };

    if (fm) {
        QFont fStatus, fFreq, fName;
        qreal h1 = 0, h2 = 0, h3 = 0, totalH = 0;
        const qreal gapY = 2.0;
        fitFonts(8, 15, 7, 3, 0.0, gapY, fStatus, fFreq, fName, h1, h2, h3, totalH);
        qreal y = info.top() + qMax(0.0, (info.height() - totalH) * 0.5);

        p.setFont(fStatus);
        p.setPen(glow);
        p.drawText(QRectF(info.left(), y, info.width() * 0.62, h1),
                   Qt::AlignLeft | Qt::AlignVCenter,
                   m_radioLocked ? QStringLiteral("FM  STEREO") : QStringLiteral("FM  TUNING"));
        p.setPen(m_sleepPresetMin > 0 ? QColor(255, 170, 50)
                                      : (m_playing ? QColor(90, 230, 130) : QColor(200, 110, 40)));
        p.drawText(QRectF(info.left() + info.width() * 0.55, y, info.width() * 0.45, h1),
                   Qt::AlignRight | Qt::AlignVCenter,
                   m_sleepPresetMin > 0
                       ? sleepStatusText()
                       : (m_playing ? QStringLiteral("ON AIR") : QStringLiteral("STANDBY")));
        y += h1 + gapY;

        p.setFont(fFreq);
        p.setPen(glow);
        p.drawText(QRectF(info.left(), y, info.width(), h2),
                   Qt::AlignLeft | Qt::AlignVCenter,
                   QStringLiteral("%1 MHz").arg(m_frequency, 0, 'f', 1));
        y += h2 + gapY;

        p.setFont(fName);
        p.setPen(QColor(220, 120, 35));
        const QString label = m_radioLocked
            ? (m_radioName.isEmpty() ? m_trackName : m_radioName)
            : QStringLiteral("— NO SIGNAL —");
        p.drawText(QRectF(info.left(), y, info.width(), h3),
                   Qt::AlignLeft | Qt::AlignVCenter,
                   QFontMetrics(fName).elidedText(label, Qt::ElideRight, int(info.width())));

        m_progressRect = QRectF();
    } else {
        QFont fMode, fTime, fTrack;
        qreal hMode = 0, hTime = 0, hTrack = 0, totalH = 0;
        const qreal barH = 4.0;
        const qreal gapY = 2.0;
        fitFonts(8, 13, 7, 4, barH, gapY, fMode, fTime, fTrack, hMode, hTime, hTrack, totalH);
        qreal y = info.top() + qMax(0.0, (info.height() - totalH) * 0.5);

        p.setFont(fMode);
        p.setPen(glow);
        p.drawText(QRectF(info.left(), y, info.width() * 0.55, hMode),
                   Qt::AlignLeft | Qt::AlignVCenter,
                   m_playing ? QStringLiteral("TAPE  A") : QStringLiteral("TAPE"));
        p.setPen(m_sleepPresetMin > 0 ? QColor(255, 170, 50) : QColor(200, 120, 40));
        p.drawText(QRectF(info.left() + info.width() * 0.45, y, info.width() * 0.55, hMode),
                   Qt::AlignRight | Qt::AlignVCenter,
                   m_sleepPresetMin > 0 ? sleepStatusText() : playModeLabel(m_playMode));
        y += hMode + gapY;

        p.setFont(fTime);
        p.setPen(glow);
        p.drawText(QRectF(info.left(), y, info.width() * 0.48, hTime),
                   Qt::AlignLeft | Qt::AlignVCenter, m_timeText);
        p.setFont(QFont(QStringLiteral("Consolas"), qMax(7, fTime.pointSize() - 4), QFont::Bold));
        p.setPen(QColor(200, 110, 35));
        p.drawText(QRectF(info.left() + info.width() * 0.50, y, info.width() * 0.50, hTime),
                   Qt::AlignRight | Qt::AlignVCenter, m_durationText);
        y += hTime + gapY;

        p.setFont(fTrack);
        p.setPen(QColor(220, 130, 40));
        p.drawText(QRectF(info.left(), y, info.width(), hTrack),
                   Qt::AlignLeft | Qt::AlignVCenter,
                   QFontMetrics(fTrack).elidedText(m_trackName, Qt::ElideRight, int(info.width())));
        y += hTrack + gapY;

        m_progressRect = QRectF(info.left(), y, info.width(), barH);
        p.setBrush(QColor(40, 22, 8));
        p.setPen(Qt::NoPen);
        p.drawRect(m_progressRect);
        p.setBrush(QColor(255, 150, 40));
        p.drawRect(QRectF(m_progressRect.left(), m_progressRect.top(),
                          m_progressRect.width() * m_progress, m_progressRect.height()));
    }

    PaintKit::drawGlassReflection(p, rect);
    p.setPen(QPen(QColor(255, 255, 255, 35), 1));
    p.drawLine(rect.left() + 2, rect.top() + 1, rect.right() - 2, rect.top() + 1);
    p.restore();
}

void CassetteDeckWidget::drawVerticalFader(QPainter &p, const QRectF &track, float value,
                                          const QString &label, const QString &key, bool bipolar)
{
    PaintKit::fillBeveledRect(p, track, QColor(10, 10, 12), 1.5, 2, false);
    // Scale ticks
    p.setPen(QPen(QColor(70, 70, 74), 1));
    for (int i = 0; i <= 4; ++i) {
        const qreal y = track.top() + track.height() * i / 4.0;
        p.drawLine(QPointF(track.left() + 2, y), QPointF(track.left() + 5, y));
        p.drawLine(QPointF(track.right() - 5, y), QPointF(track.right() - 2, y));
    }
    if (bipolar) {
        const qreal midY = track.center().y();
        p.setPen(QPen(QColor(120, 90, 40), 1));
        p.drawLine(QPointF(track.left() + 1, midY), QPointF(track.right() - 1, midY));
    }

    const float v = PaintKit::clamp01(value);
    const qreal y = track.bottom() - v * track.height();
    const QRectF cap(track.center().x() - track.width() * 0.42, y - 5, track.width() * 0.84, 10);
    QLinearGradient g(cap.topLeft(), cap.bottomLeft());
    g.setColorAt(0.0, QColor(210, 210, 216));
    g.setColorAt(0.45, QColor(120, 120, 128));
    g.setColorAt(1.0, QColor(48, 48, 54));
    p.setBrush(g);
    p.setPen(QPen(QColor(30, 30, 34), 1));
    p.drawRoundedRect(cap, 2, 2);
    p.setPen(QPen(QColor(255, 60, 40), 1.4));
    p.drawLine(QPointF(cap.left() + 2, cap.center().y()), QPointF(cap.right() - 2, cap.center().y()));

    PaintKit::drawLabel(p, QRectF(track.left() - 6, track.bottom() + 2, track.width() + 12, 11),
                        label, 5, true, QColor(170, 170, 174));
    m_sliderTracks[key] = track;
    m_hit[key] = track.adjusted(-4, -6, 4, 14);
}

void CassetteDeckWidget::drawAmpModule(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);
    m_sliderTracks.clear();
    const UiTheme &th = m_theme;
    const QRectF face = rect.adjusted(6, 4, -6, -4);
    PaintKit::fillBeveledRect(p, face, th.ampFace, 2.8, 4.0, true);
    p.setOpacity(0.30);
    p.drawPixmap(face.toRect(), PaintKit::plasticNoise(int(face.width()), int(face.height()), 33, 9));
    p.setOpacity(0.16);
    p.drawPixmap(face.toRect(), PaintKit::brushedMetal(int(face.width()), int(face.height()), 11));
    p.setOpacity(1.0);
    PaintKit::paintWornOverlay(p, face, 23);

    // 面板顶栏：标题 + 数字读数
    const qreal hdrH = 16.0;
    PaintKit::drawLabel(p, QRectF(face.left() + 10, face.top() + 2, 88, hdrH - 2),
                        QStringLiteral("AMP  CONTROL"), 6, true, th.labelDim,
                        Qt::AlignLeft | Qt::AlignVCenter, 0.7);
    const QRectF digi(face.right() - 168, face.top() + 2, 156, hdrH - 1);
    PaintKit::fillBeveledRect(p, digi, th.ampWell, 1.5, 2, false);
    {
        QLinearGradient digiG(digi.topLeft(), digi.bottomLeft());
        digiG.setColorAt(0.0, QColor(th.vfdGlow.red(), th.vfdGlow.green(), th.vfdGlow.blue(), 28));
        digiG.setColorAt(1.0, Qt::transparent);
        p.fillRect(digi.adjusted(1, 1, -1, -1), digiG);
        const int volDb = m_mute ? -99 : int(std::round(-48.0 + 48.0 * m_volume));
        const QString digiText = QStringLiteral("%1  %2dB  %3")
                                     .arg(m_sourceMode)
                                     .arg(volDb, 3)
                                     .arg(m_preset.isEmpty() ? QStringLiteral("USER") : m_preset);
        PaintKit::drawLabel(p, digi.adjusted(4, 0, -4, 0), digiText, 7, true, th.vfdGlow,
                            Qt::AlignCenter, 0.5);
    }

    // —— 上排：音效预设 ——
    const qreal topH = qBound(22.0, face.height() * 0.17, 28.0);
    const QStringList presets = {
        QStringLiteral("ROCK"), QStringLiteral("POPS"), QStringLiteral("CLASSIC"),
        QStringLiteral("JAZZ"), QStringLiteral("DISCO"), QStringLiteral("FLAT"),
        QStringLiteral("VOCAL")};
    const QRectF presetRow(face.left() + 8, face.top() + hdrH + 1, face.width() - 16, topH - 1);
    PaintKit::drawLabel(p, QRectF(presetRow.left(), presetRow.top(), 48, 8),
                        QStringLiteral("EQ PRESET"), 5, true, th.labelDim,
                        Qt::AlignLeft | Qt::AlignVCenter, 0.6);
    const qreal slot = (presetRow.width() - 4) / presets.size();
    for (int i = 0; i < presets.size(); ++i) {
        const qreal cx = presetRow.left() + (i + 0.5) * slot;
        const bool on = (m_preset == presets[i]);
        const QRectF chip(cx - slot * 0.42, presetRow.top() + 8, slot * 0.84, presetRow.height() - 10);
        if (on) {
            p.setPen(QPen(th.accent, 1.0));
            p.setBrush(QColor(th.accent.red(), th.accent.green(), th.accent.blue(), 35));
            p.drawRoundedRect(chip, 2, 2);
        }
        PaintKit::drawLabel(p, chip, QStringLiteral("%1").arg(presets[i]),
                            5, true, on ? th.labelHot : th.label);
        PaintKit::drawLed(p, QPointF(cx, presetRow.top() + 5), on, th.ledWarm, 1.7);
        m_hit[QStringLiteral("preset:%1").arg(presets[i])] = chip.adjusted(-2, -6, 2, 2);
    }

    // —— 中排：功能键分三组（FX / CTRL / SYS）——
    const qreal swH = qBound(17.0, face.height() * 0.13, 22.0);
    const qreal swY = presetRow.bottom() + 2;
    const QStringList swLabs = {
        QStringLiteral("DOLBY"), QStringLiteral("MEGA"), QStringLiteral("LOUD"),
        QStringLiteral("MUTE"), QStringLiteral("SURR"), QStringLiteral("WIDE"),
        QStringLiteral("BOOST"), QStringLiteral("PEAK"), vizModeLabel(), sleepStatusText()};
    const QStringList swKeys = {
        QStringLiteral("amp:dolby"), QStringLiteral("amp:megabass"), QStringLiteral("amp:loudness"),
        QStringLiteral("amp:mute"), QStringLiteral("amp:surround"), QStringLiteral("amp:wide"),
        QStringLiteral("amp:boost"), QStringLiteral("amp:peak"), QStringLiteral("amp:viz"),
        QStringLiteral("amp:sleep")};
    const bool swLit[] = {
        m_dolby, m_megaBass, m_loudness, m_mute, m_surround, m_stereoWide,
        m_dynBoost, m_peakHold, true, m_sleepPresetMin > 0};
    const int swN = swLabs.size();
    const qreal swGap = 2.5;
    const qreal swW = (face.width() - 16 - swGap * (swN - 1)) / swN;
    for (int i = 0; i < swN; ++i) {
        flatKey(p, QRectF(face.left() + 8 + i * (swW + swGap), swY, swW, swH - 1),
                swLabs[i], swKeys[i], swLit[i], true);
    }

    // —— 下排：EQ 推子 | 灯柱 | 频谱 | 峰值 | 旋钮 ——
    const qreal captionH = 11.0;
    const QRectF body(face.left() + 8, swY + swH + 2,
                      face.width() - 16, face.bottom() - captionH - 2 - (swY + swH + 2));
    if (body.height() < 26) {
        p.restore();
        return;
    }

    const qreal faderW = 13;
    const qreal faderGap = 10;
    const qreal faderH = qMax(24.0, body.height() - 12);
    const qreal faderTop = body.top() + 1;
    qreal fx = body.left() + 2;
    drawVerticalFader(p, QRectF(fx, faderTop, faderW, faderH), m_bass,
                       QStringLiteral("BASS"), QStringLiteral("amp:bass"));
    fx += faderW + faderGap;
    drawVerticalFader(p, QRectF(fx, faderTop, faderW, faderH), m_mid,
                       QStringLiteral("MID"), QStringLiteral("amp:mid"));
    fx += faderW + faderGap;
    drawVerticalFader(p, QRectF(fx, faderTop, faderW, faderH), m_treble,
                       QStringLiteral("TREBLE"), QStringLiteral("amp:treble"));
    fx += faderW + faderGap;
    drawVerticalFader(p, QRectF(fx, faderTop, faderW, faderH), m_balance,
                       QStringLiteral("BAL"), QStringLiteral("amp:balance"), true);
    fx += faderW + faderGap + 3;

    // DBFB 灯柱
    const QRectF db(fx, faderTop, 8, faderH);
    PaintKit::fillBeveledRect(p, db, th.ampWell, 1, 2, false);
    if (m_megaBass || m_dynBoost) {
        QLinearGradient g(db.bottomLeft(), db.topLeft());
        g.setColorAt(0.0, th.ledDanger.darker(140));
        g.setColorAt(0.55, th.accentHot);
        g.setColorAt(1.0, th.vfdGlow);
        p.fillRect(db.adjusted(1.2, 1.2, -1.2, -1.2), g);
    }
    PaintKit::drawLabel(p, QRectF(db.left() - 8, db.bottom() + 1, 24, 10),
                        QStringLiteral("DBFB"), 5, true,
                        (m_megaBass || m_dynBoost) ? th.accentHot : th.labelDim);
    fx = db.right() + 8;

    // 频谱分析仪
    const qreal meterW = qBound(64.0, body.width() * 0.20, 128.0);
    const QRectF meter(fx, faderTop, meterW, faderH);
    PaintKit::fillBeveledRect(p, meter, th.ampWell, 1.5, 2, false);
    const QRectF meterIn = meter.adjusted(3, 3, -3, -12);
    const int bars = qMax(8, int(meterIn.width() / 5));
    for (int i = 0; i < bars; ++i) {
        const float t = float(i) / float(qMax(1, bars - 1));
        const int bi = int(t * qMax(0, m_bands.size() - 1));
        float v = m_bands.isEmpty() ? 0.15f : m_bands[bi];
        if (m_dolby)
            v *= (0.75f + 0.25f * (1.f - t));
        if (m_stereoWide)
            v *= (0.92f + 0.16f * qAbs(t - 0.5f) * 2.f);
        const qreal bh = meterIn.height() * PaintKit::clamp01(v);
        const qreal bx = meterIn.left() + i * (meterIn.width() / bars);
        const qreal bw = qMax(2.0, meterIn.width() / bars - 1.2);
        QLinearGradient bg(QPointF(bx, meterIn.bottom()), QPointF(bx, meterIn.bottom() - bh));
        bg.setColorAt(0.0, th.ledCool.darker(120));
        bg.setColorAt(0.55, th.accent);
        bg.setColorAt(1.0, th.ledDanger);
        p.fillRect(QRectF(bx, meterIn.bottom() - bh, bw, bh), bg);
        if (m_peakHold && bi < m_peaks.size()) {
            const qreal py = meterIn.bottom() - meterIn.height() * PaintKit::clamp01(m_peaks[bi]);
            p.fillRect(QRectF(bx, py, bw, 1.6), th.vfdGlow);
        }
    }
    PaintKit::drawLabel(p, QRectF(meter.left(), meter.bottom() - 11, meter.width(), 10),
                        QStringLiteral("ANALYZER · %1").arg(vizModeLabel()), 5, true, th.labelDim);
    m_hit[QStringLiteral("amp:viz")] = meter;
    PaintKit::drawLed(p, QPointF(meter.right() - 8, meter.top() + 6), m_dolby, th.ledCool, 1.8);
    PaintKit::drawLabel(p, QRectF(meter.right() - 34, meter.top() + 1, 24, 8),
                        QStringLiteral("NR"), 5, true,
                        m_dolby ? th.ledCool : th.labelDim,
                        Qt::AlignRight | Qt::AlignVCenter);
    fx = meter.right() + 8;

    // L/R 峰值条
    const qreal peakW = 18;
    const QRectF peakBox(fx, faderTop, peakW, faderH);
    PaintKit::fillBeveledRect(p, peakBox, th.ampWell, 1.2, 2, false);
    auto drawPeak = [&](qreal x, float lv, const QColor &c) {
        const qreal ph = (peakBox.height() - 14) * PaintKit::clamp01(lv);
        p.fillRect(QRectF(x, peakBox.bottom() - 12 - ph, 5, ph), c);
    };
    drawPeak(peakBox.left() + 3, m_left * (m_stereoWide ? 1.08f : 1.f), th.ledCool);
    drawPeak(peakBox.left() + 10, m_right * (m_stereoWide ? 1.08f : 1.f), th.accentHot);
    PaintKit::drawLabel(p, QRectF(peakBox.left() - 2, peakBox.bottom() - 11, peakW + 4, 10),
                        QStringLiteral("L R"), 5, true, th.labelDim);
    fx = peakBox.right() + 10;

    // 旋钮区
    const qreal knobsW = body.right() - fx - 2;
    const qreal maxR = qMin(22.0, body.height() * 0.32);
    const qreal volR = qBound(11.0, maxR, 20.0);
    const qreal smallR = qBound(8.0, volR * 0.58, 13.0);
    const qreal cy = body.center().y() - 3;
    const QPointF mic(fx + knobsW * 0.18, cy);
    const QPointF vol(fx + knobsW * 0.50, cy);
    const QPointF echo(fx + knobsW * 0.82, cy);
    PaintKit::drawKnob(p, mic, smallR, m_micLevel, th.accent);
    PaintKit::drawKnob(p, vol, volR, m_mute ? 0.f : m_volume,
                       m_mute ? th.labelDim : th.ledDanger);
    PaintKit::drawKnob(p, echo, smallR, m_echoLevel, th.accentHot);
    m_knobCenter = vol;
    m_hit[QStringLiteral("volume")] = QRectF(vol.x() - volR - 8, vol.y() - volR - 8,
                                             (volR + 8) * 2, (volR + 8) * 2);
    m_hit[QStringLiteral("amp:mic")] = QRectF(mic.x() - smallR - 6, mic.y() - smallR - 6,
                                              (smallR + 6) * 2, (smallR + 6) * 2);
    m_hit[QStringLiteral("amp:echo")] = QRectF(echo.x() - smallR - 6, echo.y() - smallR - 6,
                                               (smallR + 6) * 2, (smallR + 6) * 2);

    const qreal labY = face.bottom() - captionH;
    PaintKit::drawLabel(p, QRectF(mic.x() - 34, labY, 68, captionH), QStringLiteral("MIC"), 5, true, th.labelDim);
    PaintKit::drawLabel(p, QRectF(vol.x() - 34, labY, 68, captionH),
                        m_mute ? QStringLiteral("MUTE") : QStringLiteral("VOLUME"), 6,
                        true, m_mute ? th.ledDanger : th.label);
    PaintKit::drawLabel(p, QRectF(echo.x() - 34, labY, 68, captionH), QStringLiteral("ECHO"), 5, true, th.labelDim);

    PaintKit::drawLed(p, QPointF(face.right() - 50, face.bottom() - 14), m_stereoWide, th.ledCool, 2.0);
    PaintKit::drawLed(p, QPointF(face.right() - 34, face.bottom() - 14), m_surround, th.accentHot, 2.0);
    PaintKit::drawLed(p, QPointF(face.right() - 18, face.bottom() - 14),
                      m_sleepPresetMin > 0, th.ledWarm, 2.0);
    p.restore();
}

void CassetteDeckWidget::drawRadioPowerSwitch(QPainter &p, const QRectF &rect)
{
    // Vintage rocker: recessed bezel + illuminated ON half
    PaintKit::fillBeveledRect(p, rect, QColor(18, 18, 20), 2, 3, false);
    const QRectF well = rect.adjusted(2, 2, -2, -2);
    const qreal mid = well.center().x();
    const QRectF offHalf(well.left(), well.top(), mid - well.left(), well.height());
    const QRectF onHalf(mid, well.top(), well.right() - mid, well.height());

    const bool pressed = m_pressed == QLatin1String("radio:power");
    const bool hover = m_hover == QLatin1String("radio:power");

    if (m_radioPower) {
        QLinearGradient onG(onHalf.topLeft(), onHalf.bottomLeft());
        onG.setColorAt(0.0, QColor(210, 55, 40));
        onG.setColorAt(0.45, QColor(160, 28, 22));
        onG.setColorAt(1.0, QColor(90, 16, 12));
        p.fillRect(onHalf.adjusted(0, pressed ? 1 : 0, 0, 0), onG);
        QLinearGradient offG(offHalf.topLeft(), offHalf.bottomLeft());
        offG.setColorAt(0.0, QColor(42, 42, 46));
        offG.setColorAt(1.0, QColor(22, 22, 24));
        p.fillRect(offHalf, offG);
    } else {
        QLinearGradient offG(offHalf.topLeft(), offHalf.bottomLeft());
        offG.setColorAt(0.0, hover ? QColor(70, 70, 76) : QColor(58, 58, 62));
        offG.setColorAt(1.0, QColor(28, 28, 30));
        p.fillRect(offHalf.adjusted(0, pressed ? 1 : 0, 0, 0), offG);
        QLinearGradient onG(onHalf.topLeft(), onHalf.bottomLeft());
        onG.setColorAt(0.0, QColor(36, 36, 40));
        onG.setColorAt(1.0, QColor(16, 16, 18));
        p.fillRect(onHalf, onG);
    }

    p.setPen(QPen(QColor(0, 0, 0, 160), 1));
    p.drawLine(QPointF(mid, well.top() + 1), QPointF(mid, well.bottom() - 1));
    PaintKit::drawLabel(p, offHalf, QStringLiteral("OFF"), 5, true,
                        m_radioPower ? QColor(110, 110, 114) : QColor(230, 230, 234));
    PaintKit::drawLabel(p, onHalf, QStringLiteral("ON"), 5, true,
                        m_radioPower ? QColor(255, 220, 180) : QColor(90, 90, 94));
    PaintKit::drawLed(p, QPointF(rect.left() - 8, rect.center().y()), m_radioPower,
                      QColor(255, 40, 30), 2.1);
    m_hit[QStringLiteral("radio:power")] = rect.adjusted(-14, 0, 0, 0);
}

void CassetteDeckWidget::drawRadioModule(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);
    const QRectF face = rect.adjusted(6, 4, -6, -4);
    PaintKit::fillBeveledRect(p, face, QColor(28, 28, 32), 2, 3, true);
    p.setOpacity(0.20);
    p.drawPixmap(face.toRect(), PaintKit::plasticNoise(int(face.width()), int(face.height()), 77, 5));
    p.setOpacity(1.0);

    const qreal headerH = 12.0;
    const qreal footerH = qBound(18.0, face.height() * 0.18, 24.0);
    PaintKit::drawLabel(p, QRectF(face.left() + 12, face.top() + 1, 120, headerH),
                        QStringLiteral("FM / AM  TUNER"), 6, true, QColor(150, 150, 154),
                        Qt::AlignLeft | Qt::AlignVCenter);
    PaintKit::drawLabel(p, QRectF(face.center().x() - 70, face.top() + 1, 140, headerH),
                        m_radioRegionName.isEmpty() ? QStringLiteral("—") : m_radioRegionName,
                        7, true, m_radioPower ? QColor(255, 180, 90) : QColor(160, 150, 120));
    PaintKit::drawLabel(p, QRectF(face.right() - 120, face.top() + 1, 108, headerH),
                        QStringLiteral("QUARTZ LOCK"), 6, true,
                        m_radioPower ? QColor(200, 170, 80) : QColor(100, 90, 50),
                        Qt::AlignRight | Qt::AlignVCenter);

    const qreal sideW = qBound(88.0, face.width() * 0.16, 120.0);
    const QRectF dialWell(face.left() + 10, face.top() + headerH + 2,
                          face.width() - sideW - 22, face.height() - headerH - footerH - 4);
    PaintKit::fillBeveledRect(p, dialWell, QColor(42, 42, 46), 2, 3, true);
    const QRectF glass = dialWell.adjusted(3, 3, -3, -3);
    QLinearGradient dialBg(glass.topLeft(), glass.bottomLeft());
    if (m_radioPower) {
        dialBg.setColorAt(0.0, QColor(236, 228, 205));
        dialBg.setColorAt(0.55, QColor(222, 212, 188));
        dialBg.setColorAt(1.0, QColor(200, 190, 165));
    } else {
        dialBg.setColorAt(0.0, QColor(120, 116, 105));
        dialBg.setColorAt(0.55, QColor(95, 90, 80));
        dialBg.setColorAt(1.0, QColor(72, 68, 60));
    }
    p.fillRect(glass, dialBg);

    // Keep scale + station tags fully inside glass (never flush to the cream edge)
    const qreal topPad = qMin(14.0, glass.height() * 0.28);
    const qreal botPad = glass.height() >= 52 ? 14.0 : qMax(4.0, glass.height() * 0.12);
    m_dialRect = glass.adjusted(8, topPad, -8, -botPad);

    p.setPen(QPen(QColor(40, 32, 22), 1));
    for (int mhz = 88; mhz <= 108; mhz += 1) {
        const qreal x = dialXFromFreq(float(mhz));
        const bool major = (mhz % 2 == 0);
        p.drawLine(QPointF(x, m_dialRect.top()),
                   QPointF(x, m_dialRect.top() + (major ? 8 : 4)));
        if (major && m_dialRect.height() >= 18) {
            PaintKit::drawLabel(p, QRectF(x - 12, m_dialRect.top() + 8, 24, 10),
                                QString::number(mhz), 5, true, QColor(50, 40, 28));
        }
    }
    PaintKit::drawLabel(p, QRectF(glass.left() + 4, glass.top() + 1, 40, 11),
                        QStringLiteral("MHz"), 6, true, QColor(80, 60, 40),
                        Qt::AlignLeft | Qt::AlignVCenter);
    PaintKit::drawLabel(p, QRectF(glass.right() - 36, glass.top() + 1, 32, 11),
                        QStringLiteral("FM"), 7, true, QColor(140, 40, 30),
                        Qt::AlignRight | Qt::AlignVCenter);

    for (int i = 0; i < m_radioMarkers.size(); ++i) {
        const qreal x = dialXFromFreq(m_radioMarkers[i]);
        p.setBrush(QColor(180, 40, 30));
        p.setPen(Qt::NoPen);
        p.drawEllipse(QPointF(x, m_dialRect.bottom() - 2), 2.0, 2.0);
        // Short labels only when there is room above the bottom edge
        if (botPad >= 11 && i < m_radioLabels.size()) {
            PaintKit::drawLabel(p, QRectF(x - 14, m_dialRect.bottom() - 11, 28, 9),
                                m_radioLabels[i], 4, true, QColor(90, 50, 40));
        }
    }

    const qreal nx = dialXFromFreq(m_frequency);
    p.setPen(QPen(QColor(200, 30, 30), 1.6));
    p.drawLine(QPointF(nx, glass.top() + 3), QPointF(nx, glass.bottom() - 3));
    p.setBrush(QColor(220, 40, 35));
    p.setPen(Qt::NoPen);
    QPolygonF tip;
    tip << QPointF(nx, glass.top() + 2)
        << QPointF(nx - 4, glass.top() + 10)
        << QPointF(nx + 4, glass.top() + 10);
    p.drawPolygon(tip);
    PaintKit::drawGlassReflection(p, glass);
    m_hit[QStringLiteral("radio:dial")] = glass;

    // Right side: 先从底部锁定 TUNING 旋钮，再在上方排 LED / SIGNAL，杜绝重叠
    const QRectF side(dialWell.right() + 8, dialWell.top(),
                      face.right() - dialWell.right() - 14, dialWell.height());
    const bool live = m_radioPower;

    const qreal tuneCaptionH = 11.0;
    const qreal gapAboveKnob = 6.0;
    qreal knobR = qBound(8.0, qMin(13.0, side.height() * 0.18), 13.0);
    // 若高度不够，优先缩小旋钮，保证上方仍有 SIGNAL 区
    const qreal minTopStack = 44.0; // TUNED+STEREO+SIGNAL 最小高度
    while (knobR > 7.0 && (tuneCaptionH + knobR * 2 + gapAboveKnob + minTopStack) > side.height())
        knobR -= 0.5;

    const bool showTuneCaption = (side.height() >= knobR * 2 + tuneCaptionH + minTopStack);
    const qreal knobY = side.bottom() - (showTuneCaption ? tuneCaptionH : 1.0) - knobR;
    m_tuneKnobCenter = QPointF(side.center().x(), knobY);
    const qreal stackBottom = knobY - knobR - gapAboveKnob; // SIGNAL 不得越过此线

    qreal sy = side.top() + 2;
    PaintKit::drawLed(p, QPointF(side.left() + 10, sy + 6), live && m_radioLocked, QColor(40, 220, 90), 2.2);
    PaintKit::drawLabel(p, QRectF(side.left() + 20, sy, side.width() - 22, 12),
                        QStringLiteral("TUNED"), 6, true, QColor(170, 170, 174),
                        Qt::AlignLeft | Qt::AlignVCenter);
    sy += 13;
    PaintKit::drawLed(p, QPointF(side.left() + 10, sy + 6),
                      live && m_radioLocked && m_playing && m_sourceMode == QLatin1String("FM"),
                      QColor(80, 160, 255), 2.2);
    PaintKit::drawLabel(p, QRectF(side.left() + 20, sy, side.width() - 22, 12),
                        QStringLiteral("STEREO"), 6, true, QColor(170, 170, 174),
                        Qt::AlignLeft | Qt::AlignVCenter);
    sy += 14;

    // SIGNAL：整块必须落在旋钮顶之上
    if (sy + 18.0 <= stackBottom) {
        PaintKit::drawLabel(p, QRectF(side.left() + 4, sy, side.width() - 8, 10),
                            QStringLiteral("SIGNAL"), 5, true, QColor(120, 120, 124));
        sy += 11;
        const qreal sigH = qMin(7.0, stackBottom - sy - 1.0);
        if (sigH >= 4.0) {
            const QRectF sig(side.left() + 4, sy, side.width() - 8, sigH);
            PaintKit::fillBeveledRect(p, sig, QColor(12, 12, 14), 1, 2, false);
            const int segs = 10;
            const float sigLevel = live ? m_radioSignal : 0.f;
            for (int i = 0; i < segs; ++i) {
                const qreal sw = (sig.width() - 4) / segs;
                const QRectF s(sig.left() + 2 + i * sw, sig.top() + 1.0, sw - 1.1, sig.height() - 2.0);
                const bool on = i < int(sigLevel * segs + 0.01f);
                p.setBrush(on ? (i > 7 ? QColor(255, 60, 40) : QColor(255, 160, 40)) : QColor(40, 28, 12));
                p.setPen(Qt::NoPen);
                p.drawRect(s);
            }
        }
    }

    const float tuneVal = (m_frequency - m_fmMin) / (m_fmMax - m_fmMin);
    PaintKit::drawKnob(p, m_tuneKnobCenter, knobR, tuneVal, QColor(230, 40, 35));
    if (showTuneCaption) {
        PaintKit::drawLabel(p, QRectF(m_tuneKnobCenter.x() - 28, m_tuneKnobCenter.y() + knobR + 1, 56, 10),
                            QStringLiteral("TUNING"), 5, true, QColor(150, 150, 154));
    }
    m_hit[QStringLiteral("radio:tune")] = QRectF(m_tuneKnobCenter.x() - knobR - 4,
                                                 m_tuneKnobCenter.y() - knobR - 4,
                                                 (knobR + 4) * 2, (knobR + 4) * 2);

    // Footer: scan + CITY + POWER rocker
    const qreal by = face.bottom() - footerH + 2;
    const qreal keyH = footerH - 4;
    transportKey(p, QRectF(face.left() + 10, by, 22, keyH), PaintKit::TransportIcon::Prev,
                 QStringLiteral("radio:prev"), false, true);
    transportKey(p, QRectF(face.left() + 36, by, 22, keyH), PaintKit::TransportIcon::Next,
                 QStringLiteral("radio:next"), false, true);
    flatKey(p, QRectF(face.left() + 64, by, 52, keyH), QStringLiteral("CITY"),
            QStringLiteral("radio:region"), false);
    PaintKit::drawLabel(p, QRectF(face.left() + 122, by, 120, keyH),
                        QStringLiteral("%1  ·  %2 MHz")
                            .arg(m_radioRegionName)
                            .arg(m_frequency, 0, 'f', 1),
                        6, true,
                        (live && m_radioLocked) ? QColor(255, 170, 60) : QColor(160, 160, 164),
                        Qt::AlignLeft | Qt::AlignVCenter);

    PaintKit::drawLabel(p, QRectF(face.right() - 148, by, 48, keyH),
                        QStringLiteral("POWER"), 6, true, QColor(150, 150, 154),
                        Qt::AlignRight | Qt::AlignVCenter);
    drawRadioPowerSwitch(p, QRectF(face.right() - 92, by, 78, keyH));
    p.restore();
}

bool CassetteDeckWidget::hasTapeLoaded() const
{
    return !m_playlistTitles.isEmpty()
           || (!m_trackName.isEmpty()
               && m_trackName != QLatin1String("NO TAPE")
               && m_trackName != QLatin1String("未装入磁带")
               && m_sourceMode != QLatin1String("FM"));
}

int CassetteDeckWidget::currentLyricIndex() const
{
    if (m_lyrics.isEmpty())
        return -1;
    qint64 pos = 0;
    if (m_progress > 0.f)
        pos = qint64(m_progress * qMax<qint64>(1, m_lyrics.last().timeMs + 5000));
    int idx = 0;
    for (int i = 0; i < m_lyrics.size(); ++i) {
        if (m_lyrics[i].timeMs <= pos)
            idx = i;
        else
            break;
    }
    return idx;
}

QPixmap CassetteDeckWidget::makeProceduralCover(const QString &title) const
{
    const int s = 512;
    QPixmap pm(s, s);
    pm.fill(Qt::black);
    QPainter gp(&pm);
    gp.setRenderHint(QPainter::Antialiasing, true);
    const uint h = uint(qHash(title));
    const int hue = int(h % 360);
    QLinearGradient g(0, 0, s, s);
    g.setColorAt(0.0, QColor::fromHsv(hue, 160, 55));
    g.setColorAt(0.45, QColor::fromHsv((hue + 40) % 360, 180, 35));
    g.setColorAt(1.0, QColor::fromHsv((hue + 90) % 360, 140, 20));
    gp.fillRect(0, 0, s, s, g);
    QRadialGradient orb(s * 0.35, s * 0.32, s * 0.55);
    orb.setColorAt(0.0, QColor(255, 170, 80, 90));
    orb.setColorAt(1.0, QColor(0, 0, 0, 0));
    gp.fillRect(0, 0, s, s, orb);
    gp.setPen(QPen(QColor(255, 255, 255, 28), 3));
    gp.setBrush(Qt::NoBrush);
    gp.drawEllipse(QPointF(s * 0.72, s * 0.70), s * 0.22, s * 0.22);
    gp.drawEllipse(QPointF(s * 0.72, s * 0.70), s * 0.14, s * 0.14);
    gp.setBrush(QColor(255, 150, 40, 180));
    gp.setPen(Qt::NoPen);
    gp.drawEllipse(QPointF(s * 0.72, s * 0.70), s * 0.035, s * 0.035);
    gp.setPen(QColor(255, 220, 180, 220));
    QFont f(QStringLiteral("Segoe UI"), 28, QFont::Bold);
    gp.setFont(f);
    const QString line = QFontMetrics(f).elidedText(title, Qt::ElideRight, int(s * 0.78));
    gp.drawText(QRectF(s * 0.08, s * 0.12, s * 0.84, s * 0.28), Qt::AlignLeft | Qt::AlignTop, line);
    gp.setPen(QColor(255, 180, 100, 160));
    gp.setFont(QFont(QStringLiteral("Segoe UI"), 14, QFont::Bold));
    gp.drawText(QRectF(s * 0.08, s * 0.82, s * 0.84, 28), Qt::AlignLeft, QStringLiteral("拾音盒子"));
    gp.end();
    return pm;
}

void CassetteDeckWidget::drawTapeModule(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);

    const QRectF face = rect.adjusted(6, 4, -6, -4);
    PaintKit::fillBeveledRect(p, face, QColor(32, 30, 28), 2.5, 4, true);
    p.setOpacity(0.34);
    p.drawPixmap(face.toRect(), PaintKit::plasticNoise(int(face.width()), int(face.height()), 55, 12));
    p.setOpacity(1.0);
    PaintKit::paintWornOverlay(p, face, 19);

    const qreal headerH = qBound(13.0, face.height() * 0.055, 17.0);
    PaintKit::drawLabel(p, QRectF(face.left() + 12, face.top() + 2, 150, headerH),
                        QStringLiteral("CASSETTE DECK"), 6, true, QColor(210, 200, 180),
                        Qt::AlignLeft | Qt::AlignVCenter, 1.4);
    PaintKit::drawLabel(p, QRectF(face.left() + 150, face.top() + 2, 90, headerH),
                        QStringLiteral("AUTO STOP"), 5, true, QColor(120, 120, 126),
                        Qt::AlignLeft | Qt::AlignVCenter, 0.8);
    PaintKit::drawLabel(p, QRectF(face.right() - 118, face.top() + 2, 106, headerH),
                        QStringLiteral("DOLBY B-C NR"), 6, true, QColor(210, 175, 85),
                        Qt::AlignRight | Qt::AlignVCenter, 0.6);

    // Fit door + keys inside remaining height (prevents resize clipping)
    const qreal gap = 10;
    const qreal leftW = face.width() * 0.46;
    const qreal rightW = face.width() - 24 - gap - leftW;
    const qreal bodyTop = face.top() + headerH + 2;
    const qreal bodyH = face.bottom() - 4 - bodyTop;
    const qreal keyH = qBound(38.0, bodyH * 0.27, 58.0);
    const qreal doorH = qMax(48.0, bodyH - keyH - 4);
    const QRectF door(face.left() + 12, bodyTop, leftW, doorH);
    const QRectF keys(door.left(), door.bottom() + 3, leftW, keyH);
    const QRectF panel(door.right() + gap, door.top(), rightW, doorH + 3 + keyH);

    const bool tape = hasTapeLoaded();
    const bool fm = m_sourceMode == QLatin1String("FM");
    const bool tapeActive = m_playing && tape && !fm;
    // FM 已开机锁台或已装带时，运控键都应可点
    const bool transportReady = tape || (fm && m_radioPower && m_radioLocked);
    drawHiFiCassette(p, door, tape, tapeActive);
    drawDeckTransport(p, keys, transportReady, m_playing && transportReady);
    drawMediaPanel(p, panel);
    p.restore();
}

void CassetteDeckWidget::drawHiFiCassette(QPainter &p, const QRectF &rect, bool hasTape, bool playing)
{
    // ——— 厚壁黑塑料机壳 ———
    PaintKit::fillBeveledRect(p, rect, QColor(42, 40, 38), 3.0, 5.5, true);
    const QRectF chassis = rect.adjusted(2.5, 2.5, -2.5, -2.5);
    QLinearGradient shellG(chassis.topLeft(), chassis.bottomLeft());
    shellG.setColorAt(0.0, QColor(68, 64, 58));
    shellG.setColorAt(0.08, QColor(40, 38, 36));
    shellG.setColorAt(0.5, QColor(28, 26, 24));
    shellG.setColorAt(0.92, QColor(22, 20, 18));
    shellG.setColorAt(1.0, QColor(48, 44, 40));
    p.setBrush(shellG);
    p.setPen(QPen(QColor(0, 0, 0, 200), 1.2));
    p.drawRoundedRect(chassis, 2.5, 2.5);
    p.setOpacity(0.42);
    p.drawPixmap(chassis.toRect(), PaintKit::plasticNoise(int(chassis.width()), int(chassis.height()), 61, 14));
    p.setOpacity(1.0);
    PaintKit::paintWornOverlay(p, chassis, 17);
    // 厚壁内缘（塑胶壁厚）
    p.setPen(QPen(QColor(90, 82, 70, 70), 2.2));
    p.setBrush(Qt::NoBrush);
    p.drawRoundedRect(chassis.adjusted(3, 3, -3, -3), 2, 2);
    p.setPen(QPen(QColor(0, 0, 0, 90), 1.4));
    p.drawRoundedRect(chassis.adjusted(5.5, 5.5, -5.5, -5.5), 1.5, 1.5);

    // 铰链（仓门上沿）
    const qreal hingeY = chassis.top() + 5;
    p.setBrush(QColor(55, 52, 48));
    p.setPen(QPen(QColor(20, 18, 16), 0.8));
    p.drawRoundedRect(QRectF(chassis.left() + 12, hingeY - 1.5, 22, 5), 1.2, 1.2);
    p.drawRoundedRect(QRectF(chassis.right() - 34, hingeY - 1.5, 22, 5), 1.2, 1.2);
    p.setPen(QPen(QColor(140, 130, 110, 80), 1));
    p.drawLine(QPointF(chassis.left() + 36, hingeY + 1), QPointF(chassis.right() - 36, hingeY + 1));

    // ——— 仓体深井（门半开后露出来的腔） ———
    const QRectF bay = chassis.adjusted(7, 12, -7, -15);
    const QRectF pit = PaintKit::drawRecessedWell(p, bay, 2.8);
    QLinearGradient bayG(pit.topLeft(), pit.bottomLeft());
    bayG.setColorAt(0.0, QColor(6, 6, 8));
    bayG.setColorAt(0.35, QColor(10, 10, 12));
    bayG.setColorAt(1.0, QColor(16, 14, 12));
    p.fillRect(pit, bayG);
    p.setOpacity(0.3);
    p.drawPixmap(pit.toRect(), PaintKit::plasticNoise(int(pit.width()), int(pit.height()), 8, 10));
    p.setOpacity(1.0);

    // 门投下的阴影（半开）
    QLinearGradient doorShade(pit.topLeft(), pit.topLeft() + QPointF(0, pit.height() * 0.55));
    doorShade.setColorAt(0.0, QColor(0, 0, 0, 140));
    doorShade.setColorAt(0.55, QColor(0, 0, 0, 40));
    doorShade.setColorAt(1.0, QColor(0, 0, 0, 0));
    p.fillRect(pit, doorShade);

    // 仓内磁带 / 空仓机构（门抬起后完整可见）
    const QRectF loadArea = pit.adjusted(6, pit.height() * 0.18, -6, -6);
    if (hasTape) {
        const QRectF cass = loadArea.adjusted(4, 2, -4, -2);
        QLinearGradient body(cass.topLeft(), cass.bottomLeft());
        body.setColorAt(0.0, QColor(58, 62, 70));
        body.setColorAt(0.2, QColor(30, 34, 40));
        body.setColorAt(0.6, QColor(16, 18, 22));
        body.setColorAt(1.0, QColor(8, 10, 12));
        QPainterPath shell;
        shell.addRoundedRect(cass, 3.0, 3.0);
        p.fillPath(shell, body);
        p.setPen(QPen(QColor(0, 0, 0, 220), 1.4));
        p.drawPath(shell);
        p.setOpacity(0.25);
        p.drawPixmap(cass.toRect(), PaintKit::plasticNoise(int(cass.width()), int(cass.height()), 33, 8));
        p.setOpacity(1.0);
        PaintKit::paintWornOverlay(p, cass.adjusted(2, 2, -2, -2), 29);
        p.setPen(QPen(QColor(150, 155, 165, 50), 1));
        p.drawLine(cass.left() + 3, cass.top() + 1.4, cass.right() - 3, cass.top() + 1.4);
        for (const QPointF &pt : {
                 QPointF(cass.left() + 6, cass.top() + 6),
                 QPointF(cass.right() - 6, cass.top() + 6),
                 QPointF(cass.left() + 6, cass.bottom() - 6),
                 QPointF(cass.right() - 6, cass.bottom() - 6)})
            PaintKit::drawScrew(p, pt, 2.0);

        const QRectF brand(cass.left() + 12, cass.top() + 4, cass.width() - 24, 7);
        QLinearGradient brandG(brand.topLeft(), brand.bottomLeft());
        brandG.setColorAt(0.0, QColor(190, 60, 32));
        brandG.setColorAt(1.0, QColor(120, 30, 16));
        p.fillRect(brand, brandG);
        PaintKit::drawLabel(p, brand, QStringLiteral("COMPACT CASSETTE  ·  SIDE A"),
                            5, true, QColor(255, 228, 195), Qt::AlignCenter, 0.4);

        const QRectF lab(cass.left() + 12, brand.bottom() + 2, cass.width() - 24, 14);
        QLinearGradient paper(lab.topLeft(), lab.bottomLeft());
        paper.setColorAt(0.0, QColor(242, 230, 198));
        paper.setColorAt(1.0, QColor(210, 196, 160));
        p.setBrush(paper);
        p.setPen(QPen(QColor(120, 100, 70), 0.7));
        p.drawRect(lab);
        p.setPen(QPen(QColor(150, 130, 100, 80), 0.55));
        for (int i = 1; i <= 2; ++i) {
            const qreal y = lab.top() + lab.height() * i / 3.0;
            p.drawLine(QPointF(lab.left() + 3, y), QPointF(lab.right() - 3, y));
        }
        QFont lf(QStringLiteral("Segoe UI"), 7, QFont::Bold);
        p.setFont(lf);
        p.setPen(QColor(34, 26, 16));
        p.drawText(lab.adjusted(3, 0, -3, 0), Qt::AlignCenter,
                   QFontMetrics(lf).elidedText(m_trackName, Qt::ElideRight, int(lab.width() - 6)));

        const QRectF view(cass.left() + 12, lab.bottom() + 3, cass.width() - 24,
                          qMax(26.0, cass.bottom() - 12 - (lab.bottom() + 3)));
        QLinearGradient viewG(view.topLeft(), view.bottomLeft());
        viewG.setColorAt(0.0, QColor(12, 14, 16));
        viewG.setColorAt(1.0, QColor(4, 5, 6));
        p.setBrush(viewG);
        p.setPen(QPen(QColor(0, 0, 0), 1.2));
        p.drawRoundedRect(view, 2, 2);

        const qreal ry = view.center().y() + 1;
        const qreal rr = qMin(view.height() * 0.42, view.width() * 0.18);
        const qreal lx = view.left() + view.width() * 0.27;
        const qreal rx = view.left() + view.width() * 0.73;
        const float ang = playing ? m_reelAngle : 18.f;
        drawReel(p, QPointF(lx, ry), rr, ang, 1.f - m_progress);
        drawReel(p, QPointF(rx, ry), rr, -ang * 1.05f, m_progress);

        const qreal tapeY = ry + rr * 0.58;
        p.setPen(QPen(QColor(55, 35, 18), 2.4));
        p.drawLine(QPointF(lx + rr * 0.55, tapeY), QPointF(rx - rr * 0.55, tapeY));
        const QRectF pad(view.center().x() - 12, tapeY - 2.5, 24, 7);
        QLinearGradient padG(pad.topLeft(), pad.bottomLeft());
        padG.setColorAt(0.0, QColor(130, 85, 50));
        padG.setColorAt(1.0, QColor(35, 20, 12));
        p.setBrush(padG);
        p.setPen(QPen(QColor(20, 10, 5), 0.7));
        p.drawRoundedRect(pad, 1.2, 1.2);

        const QRectF slot(cass.left() + cass.width() * 0.16, cass.bottom() - 8,
                          cass.width() * 0.68, 5);
        p.setBrush(QColor(4, 4, 6));
        p.setPen(Qt::NoPen);
        p.drawRoundedRect(slot, 1, 1);
        for (qreal t : {0.22, 0.50, 0.78})
            p.drawEllipse(QPointF(slot.left() + slot.width() * t, slot.center().y()), 1.3, 1.3);
        p.drawRect(QRectF(cass.right() - 8, cass.bottom() - 14, 3.5, 6));
    } else {
        const qreal midY = loadArea.center().y();
        const qreal hubR = qMin(17.0, loadArea.height() * 0.22);
        for (qreal cxR : {0.28, 0.72}) {
            const QPointF c(loadArea.left() + loadArea.width() * cxR, midY);
            QRadialGradient flange(c - QPointF(2, 3), hubR * 1.25);
            flange.setColorAt(0.0, QColor(88, 84, 78));
            flange.setColorAt(0.45, QColor(40, 38, 36));
            flange.setColorAt(1.0, QColor(8, 8, 8));
            p.setBrush(flange);
            p.setPen(QPen(QColor(110, 105, 98), 1.1));
            p.drawEllipse(c, hubR, hubR);
            p.setBrush(QColor(4, 4, 6));
            p.setPen(Qt::NoPen);
            p.drawEllipse(c, hubR * 0.28, hubR * 0.28);
        }
        const QRectF head(loadArea.center().x() - 24, loadArea.bottom() - 18, 48, 12);
        PaintKit::fillBeveledRect(p, head, QColor(48, 46, 42), 1.5, 2.5, true);
        PaintKit::drawLabel(p, QRectF(loadArea.left(), midY - hubR - 14, loadArea.width(), 12),
                            QStringLiteral("LOAD  CASSETTE"), 7, true, QColor(100, 92, 80));
    }

    // ——— 半开仓门：顶铰链抬起，下沿朝前翻起 ———
    {
        const qreal open = 0.42; // 半开程度
        const qreal lift = bay.height() * open;
        const qreal inset = 5.0 + open * 10.0;
        // 门面板四角（透视梯形）
        const QPointF tl(bay.left() + 1, bay.top() - 1);
        const QPointF tr(bay.right() - 1, bay.top() - 1);
        const QPointF br(bay.right() - inset, bay.top() + lift);
        const QPointF bl(bay.left() + inset, bay.top() + lift);
        QPainterPath door;
        door.moveTo(tl);
        door.lineTo(tr);
        door.lineTo(br);
        door.lineTo(bl);
        door.closeSubpath();

        // 门板厚度（下沿截面）
        const qreal thick = 5.5;
        QPainterPath lip;
        lip.moveTo(bl);
        lip.lineTo(br);
        lip.lineTo(br + QPointF(0, thick));
        lip.lineTo(bl + QPointF(0, thick));
        lip.closeSubpath();
        QLinearGradient lipG(bl, bl + QPointF(0, thick));
        lipG.setColorAt(0.0, QColor(70, 64, 56));
        lipG.setColorAt(0.4, QColor(36, 32, 28));
        lipG.setColorAt(1.0, QColor(12, 10, 8));
        p.fillPath(lip, lipG);
        p.setPen(QPen(QColor(0, 0, 0, 160), 0.8));
        p.drawPath(lip);

        // 门板本体（厚塑料）
        QLinearGradient doorG(tl, bl);
        doorG.setColorAt(0.0, QColor(62, 58, 52));
        doorG.setColorAt(0.25, QColor(38, 36, 34));
        doorG.setColorAt(0.7, QColor(26, 24, 22));
        doorG.setColorAt(1.0, QColor(44, 40, 36));
        p.fillPath(door, doorG);
        p.setPen(QPen(QColor(0, 0, 0, 200), 1.2));
        p.drawPath(door);
        p.setClipPath(door);
        p.setOpacity(0.5);
        p.drawPixmap(QRectF(QPointF(qMin(tl.x(), bl.x()), tl.y()),
                            QPointF(qMax(tr.x(), br.x()), bl.y() + 1)).toRect(),
                     PaintKit::plasticNoise(int(bay.width()), int(lift + 8), 77, 16));
        p.setOpacity(1.0);
        PaintKit::paintWornOverlay(p, QRectF(bl.x(), tl.y(), br.x() - bl.x(), lift + 2), 41);
        p.setClipping(false);

        // 门上烟熏玻璃窗（随门倾斜）
        const qreal gx0 = 0.12;
        const qreal gx1 = 0.88;
        const qreal gy0 = 0.18;
        const qreal gy1 = 0.82;
        auto lerp = [](const QPointF &a, const QPointF &b, qreal t) {
            return a + (b - a) * t;
        };
        const QPointF gtl = lerp(lerp(tl, tr, gx0), lerp(bl, br, gx0), gy0);
        const QPointF gtr = lerp(lerp(tl, tr, gx1), lerp(bl, br, gx1), gy0);
        const QPointF gbr = lerp(lerp(tl, tr, gx1), lerp(bl, br, gx1), gy1);
        const QPointF gbl = lerp(lerp(tl, tr, gx0), lerp(bl, br, gx0), gy1);
        QPainterPath glass;
        glass.moveTo(gtl);
        glass.lineTo(gtr);
        glass.lineTo(gbr);
        glass.lineTo(gbl);
        glass.closeSubpath();
        QLinearGradient smoke(gtl, gbr);
        smoke.setColorAt(0.0, QColor(110, 120, 130, 70));
        smoke.setColorAt(0.35, QColor(20, 24, 30, 200));
        smoke.setColorAt(0.75, QColor(10, 12, 16, 220));
        smoke.setColorAt(1.0, QColor(70, 78, 88, 50));
        p.fillPath(glass, smoke);
        p.setPen(QPen(QColor(0, 0, 0, 160), 1));
        p.drawPath(glass);
        p.setPen(QPen(QColor(200, 210, 220, 35), 1));
        p.drawLine(gtl + QPointF(1, 1), gtr + QPointF(-1, 1));

        // 门内状态条
        const QPointF stl = lerp(gtl, gbl, 0.08);
        const QPointF str = lerp(gtr, gbr, 0.08);
        const QPointF sbr = lerp(gtr, gbr, 0.28);
        const QPointF sbl = lerp(gtl, gbl, 0.28);
        QPainterPath strip;
        strip.moveTo(stl);
        strip.lineTo(str);
        strip.lineTo(sbr);
        strip.lineTo(sbl);
        strip.closeSubpath();
        QColor stripBg = hasTape ? (playing ? QColor(255, 148, 42) : QColor(228, 214, 178))
                                 : QColor(214, 200, 168);
        p.fillPath(strip, stripBg);
        p.setPen(QPen(QColor(0, 0, 0, 80), 0.7));
        p.drawPath(strip);
        const QRectF stripBox = strip.boundingRect();
        QFont sf(QStringLiteral("Segoe UI"), 6, QFont::Bold);
        p.setFont(sf);
        p.setPen(playing ? QColor(42, 18, 0) : QColor(32, 24, 14));
        const QString stripText = hasTape
            ? (playing ? QStringLiteral("▶ PLAY  ·  DOOR AJAR") : QStringLiteral("DOOR AJAR  ·  SIDE A"))
            : QStringLiteral("DOOR AJAR  ·  LOAD TAPE");
        p.drawText(stripBox, Qt::AlignCenter,
                   QFontMetrics(sf).elidedText(stripText, Qt::ElideRight, int(stripBox.width() - 6)));

        // 门沿高光与磨损
        p.setPen(QPen(QColor(180, 170, 150, 55), 1.2));
        p.drawLine(tl + QPointF(4, 1), tr + QPointF(-4, 1));
        p.setPen(QPen(QColor(255, 240, 200, 25), 1));
        p.drawLine(bl + QPointF(2, 0), br + QPointF(-2, 0));
    }

    // 底栏铭牌区
    if (rect.height() >= 70) {
        PaintKit::drawLabel(p, QRectF(rect.left() + 8, rect.bottom() - 14, 58, 11),
                            QStringLiteral("A  PLAY"), 6, true, QColor(210, 200, 180),
                            Qt::AlignLeft | Qt::AlignVCenter, 1.0);
        const qreal modeH = 13.0;
        const qreal modeY = rect.bottom() - 15;
        const qreal mw = 40.0;
        const qreal mg = 3.0;
        qreal mx = rect.right() - 8 - (3 * mw + 2 * mg);
        flatKey(p, QRectF(mx, modeY, mw, modeH), QStringLiteral("1"),
                QStringLiteral("mode:single"), m_playMode == PlayMode::SingleLoop, true);
        mx += mw + mg;
        flatKey(p, QRectF(mx, modeY, mw, modeH), QStringLiteral("SHUF"),
                QStringLiteral("mode:random"), m_playMode == PlayMode::Random, true);
        mx += mw + mg;
        flatKey(p, QRectF(mx, modeY, mw, modeH), QStringLiteral("ALL"),
                QStringLiteral("mode:all"), m_playMode == PlayMode::AllLoop, true);
    }

    PaintKit::drawLed(p, QPointF(rect.left() + 12, rect.top() + 10), playing,
                      QColor(255, 36, 28), 2.3);
    PaintKit::drawLed(p, QPointF(rect.left() + 22, rect.top() + 10), false,
                      QColor(255, 60, 40), 2.0);
    PaintKit::drawLabel(p, QRectF(rect.left() + 28, rect.top() + 5, 36, 10),
                        QStringLiteral("PLAY"), 5, true,
                        playing ? QColor(255, 120, 80) : QColor(100, 90, 80),
                        Qt::AlignLeft | Qt::AlignVCenter);
}

void CassetteDeckWidget::drawDeckTransport(QPainter &p, const QRectF &rect, bool hasTape, bool playing)
{
    p.save();
    p.setClipRect(rect);
    // 机械运控键座：深凹槽 + 金属边
    PaintKit::fillBeveledRect(p, rect, QColor(12, 12, 14), 2, 4, false);
    const QRectF tray = rect.adjusted(3, 2, -3, -2);
    QLinearGradient trayG(tray.topLeft(), tray.bottomLeft());
    trayG.setColorAt(0.0, QColor(22, 22, 26));
    trayG.setColorAt(0.35, QColor(10, 10, 12));
    trayG.setColorAt(1.0, QColor(18, 18, 20));
    p.setBrush(trayG);
    p.setPen(QPen(QColor(0, 0, 0), 1));
    p.drawRoundedRect(tray, 2, 2);
    p.setOpacity(0.25);
    p.drawPixmap(tray.toRect(), PaintKit::brushedMetal(int(tray.width()), int(tray.height()), 3));
    p.setOpacity(1.0);

    const QRectF inner = tray.adjusted(4, 2, -4, -2);
    const bool showCaption = inner.height() >= 42;
    if (showCaption) {
        PaintKit::drawLabel(p, QRectF(inner.left(), inner.top(), 100, 10),
                            QStringLiteral("MECHANICAL KEYS"), 5, true, QColor(130, 130, 134),
                            Qt::AlignLeft | Qt::AlignVCenter, 0.8);
    }

    struct Key { const char *id; PaintKit::TransportIcon icon; const char *lab; bool play; };
    const Key keys[] = {
        {"prev", PaintKit::TransportIcon::Prev, "PREV", false},
        {"play", PaintKit::TransportIcon::Play, "PLAY", true},
        {"pause", PaintKit::TransportIcon::Pause, "PAUSE", false},
        {"stop", PaintKit::TransportIcon::Stop, "STOP", false},
        {"next", PaintKit::TransportIcon::Next, "NEXT", false},
        {"eject", PaintKit::TransportIcon::Eject, "EJECT", false},
    };
    const int n = 6;
    const qreal gap = 3;
    const qreal kw = (inner.width() - gap * (n - 1)) / n;
    const bool showLabs = inner.height() >= 38;
    const qreal labH = showLabs ? 9.0 : 0.0;
    const qreal topPad = showCaption ? 11.0 : 2.0;
    const qreal kh = qBound(17.0, inner.height() - topPad - labH - 2, 26.0);
    const qreal y = inner.top() + topPad;
    qreal x = inner.left();
    for (const Key &k : keys) {
        const QString keyId = QStringLiteral("a:") + QLatin1String(k.id);
        const bool lit = k.play && playing;
        const QLatin1String id(k.id);
        // EJECT 常开；PREV/NEXT 在 FM 下也可切台；其余随 hasTape（含 FM 锁台）
        const bool enabled = (id == QLatin1String("eject"))
                             || hasTape
                             || ((id == QLatin1String("prev") || id == QLatin1String("next"))
                                 && m_sourceMode == QLatin1String("FM"));
        // 钢琴键式机械键：略高的前缘
        const QRectF keyRect(x, y, kw, kh);
        const QRectF lip(keyRect.left(), keyRect.bottom() - 2.5, keyRect.width(), 2.5);
        p.setBrush(enabled ? QColor(18, 18, 20) : QColor(10, 10, 12));
        p.setPen(Qt::NoPen);
        p.drawRect(lip);
        transportKey(p, keyRect.adjusted(0, 0, 0, -1.5), k.icon, keyId, lit, enabled);
        if (showLabs) {
            PaintKit::drawLabel(p, QRectF(x, y + kh + 0.5, kw, labH), QString::fromLatin1(k.lab),
                                5, true, enabled ? QColor(150, 150, 155) : QColor(70, 70, 74));
        }
        x += kw + gap;
    }
    p.restore();
}

void CassetteDeckWidget::drawMediaPanel(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);
    PaintKit::fillBeveledRect(p, rect, QColor(20, 20, 24), 2.5, 4, true);
    const QRectF face = rect.adjusted(3, 3, -3, -3);
    PaintKit::fillBeveledRect(p, face, QColor(12, 12, 14), 2, 3, false);

    const QStringList tabs = {QStringLiteral("封面"), QStringLiteral("清单"),
                              QStringLiteral("歌词"), QStringLiteral("电台")};
    const qreal tabH = qBound(18.0, face.height() * 0.12, 24.0);
    const qreal tabW = face.width() / tabs.size();
    const int tabFont = face.width() < 280 ? 7 : 8;
    for (int i = 0; i < tabs.size(); ++i) {
        const QRectF tab(face.left() + i * tabW, face.top(), tabW, tabH);
        const bool on = (int(m_mediaTab) == i);
        QColor faceCol = on ? QColor(36, 36, 42) : QColor(22, 22, 26);
        if (m_hover == QStringLiteral("tab:%1").arg(i))
            faceCol = faceCol.lighter(115);
        p.fillRect(tab, faceCol);
        if (on) {
            p.setPen(QPen(QColor(255, 150, 40), 2));
            p.drawLine(tab.left() + 4, tab.bottom() - 1, tab.right() - 4, tab.bottom() - 1);
        }
        PaintKit::drawLabel(p, tab, tabs[i], tabFont, true,
                            on ? QColor(255, 180, 90) : QColor(150, 150, 155));
        m_hit[QStringLiteral("tab:%1").arg(i)] = tab;
    }
    p.setPen(QPen(QColor(50, 50, 54), 1));
    p.drawLine(face.left(), face.top() + tabH, face.right(), face.top() + tabH);

    const QRectF body = face.adjusted(4, tabH + 4, -4, -4);
    switch (m_mediaTab) {
    case MediaTab::Cover: drawCoverPage(p, body); break;
    case MediaTab::List: drawListPage(p, body); break;
    case MediaTab::Lyrics: drawLyricsPage(p, body); break;
    case MediaTab::Radio: drawRadioPage(p, body); break;
    }
    p.restore();
}

void CassetteDeckWidget::drawCoverPage(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);

    const QString title = (m_playlistIndex >= 0 && m_playlistIndex < m_playlistTitles.size())
        ? m_playlistTitles[m_playlistIndex] : m_trackName;
    QPixmap cover = m_coverArt.isNull() ? makeProceduralCover(title) : m_coverArt;

    // Reserve caption strip first so title never gets clipped outside panel
    const qreal captionH = qBound(24.0, rect.height() * 0.18, 34.0);
    const QRectF artArea(rect.left() + 6, rect.top() + 2, rect.width() - 12, rect.height() - captionH - 4);
    const qreal side = qMax(24.0, qMin(artArea.width(), artArea.height()) - 4);
    const QRectF art(artArea.center().x() - side * 0.5, artArea.center().y() - side * 0.5, side, side);

    if (side >= 40) {
        QRadialGradient sh(art.center() + QPointF(0, 4), side * 0.58);
        sh.setColorAt(0.55, QColor(0, 0, 0, 80));
        sh.setColorAt(1.0, QColor(0, 0, 0, 0));
        p.setBrush(sh);
        p.setPen(Qt::NoPen);
        p.drawEllipse(art.adjusted(-6, 2, 6, 12));

        PaintKit::fillBeveledRect(p, art.adjusted(-2, -2, 2, 2), QColor(40, 40, 44), 2, 3, true);
        p.drawPixmap(art.toRect(), cover);

        QLinearGradient gloss(art.topLeft(), art.bottomRight());
        gloss.setColorAt(0.0, QColor(255, 255, 255, 35));
        gloss.setColorAt(0.25, QColor(255, 255, 255, 0));
        gloss.setColorAt(1.0, QColor(0, 0, 0, 40));
        p.fillRect(art, gloss);
    }

    const QRectF caption(rect.left() + 4, rect.bottom() - captionH, rect.width() - 8, captionH);
    PaintKit::drawLabel(p, QRectF(caption.left(), caption.top() + 2, caption.width(), 14),
                        QFontMetrics(QFont(QStringLiteral("Segoe UI"), 8, QFont::Bold))
                            .elidedText(title, Qt::ElideRight, int(caption.width() - 4)),
                        8, true, QColor(220, 200, 160));
    const QString sub = m_playlistTitles.isEmpty()
        ? QStringLiteral("EJECT 导入歌曲")
        : QStringLiteral("%1 / %2").arg(qMax(1, m_playlistIndex + 1)).arg(m_playlistTitles.size());
    PaintKit::drawLabel(p, QRectF(caption.left(), caption.top() + 16, caption.width(), 12),
                        sub, 7, false, QColor(130, 130, 134));
    p.restore();
}

void CassetteDeckWidget::drawListPage(QPainter &p, const QRectF &rect)
{
    m_listViewport = rect;
    PaintKit::fillBeveledRect(p, rect, QColor(8, 8, 10), 1.5, 2, false);
    if (m_playlistTitles.isEmpty()) {
        PaintKit::drawLabel(p, rect, QStringLiteral("清单为空 · 按 EJECT 装带"), 8, true, QColor(90, 90, 96));
        return;
    }

    const qreal rowH = 22;
    const int visible = qMax(1, int(rect.height() / rowH));
    m_listScroll = qBound(0, m_listScroll, qMax(0, m_playlistTitles.size() - visible));
    for (int i = 0; i < visible; ++i) {
        const int idx = m_listScroll + i;
        if (idx >= m_playlistTitles.size())
            break;
        const QRectF row(rect.left() + 2, rect.top() + i * rowH, rect.width() - 4, rowH - 1);
        const bool cur = (idx == m_playlistIndex);
        const bool hover = (m_hover == QStringLiteral("list:%1").arg(idx));
        if (cur)
            p.fillRect(row, QColor(255, 140, 40, 45));
        else if (hover)
            p.fillRect(row, QColor(255, 255, 255, 18));
        PaintKit::drawLabel(p, QRectF(row.left() + 6, row.top(), 28, row.height()),
                            QStringLiteral("%1.").arg(idx + 1, 2, 10, QLatin1Char('0')),
                            7, true, cur ? QColor(255, 170, 70) : QColor(110, 110, 116),
                            Qt::AlignLeft | Qt::AlignVCenter);
        PaintKit::drawLabel(p, QRectF(row.left() + 34, row.top(), row.width() - 40, row.height()),
                            QFontMetrics(QFont(QStringLiteral("Segoe UI"), 8))
                                .elidedText(m_playlistTitles[idx], Qt::ElideRight, int(row.width() - 44)),
                            8, cur, cur ? QColor(255, 200, 120) : QColor(200, 200, 205),
                            Qt::AlignLeft | Qt::AlignVCenter);
        m_hit[QStringLiteral("list:%1").arg(idx)] = row;
    }
}

void CassetteDeckWidget::drawRadioPage(QPainter &p, const QRectF &rect)
{
    m_radioViewport = rect;
    PaintKit::fillBeveledRect(p, rect, QColor(8, 8, 10), 1.5, 2, false);

    const int count = m_radioMarkers.size();
    if (count <= 0) {
        PaintKit::drawLabel(p, rect, QStringLiteral("点 CITY 选择城市"), 8, true, QColor(90, 90, 96));
        return;
    }

    const qreal headerH = 18;
    const QRectF header(rect.left() + 4, rect.top() + 2, rect.width() - 8, headerH);
    const QString region = m_radioRegionName.isEmpty() ? QStringLiteral("电台频率") : m_radioRegionName;
    PaintKit::drawLabel(p, header,
                        QStringLiteral("%1  ·  %2 台").arg(region).arg(count),
                        7, true, QColor(180, 150, 90), Qt::AlignLeft | Qt::AlignVCenter);
    p.setPen(QPen(QColor(50, 42, 28), 1));
    p.drawLine(header.left(), header.bottom(), header.right(), header.bottom());

    const QRectF list(rect.left(), rect.top() + headerH + 4, rect.width(),
                      rect.height() - headerH - 6);
    const qreal rowH = 22;
    const int visible = qMax(1, int(list.height() / rowH));
    m_radioScroll = qBound(0, m_radioScroll, qMax(0, count - visible));

    int current = -1;
    float bestDist = 999.f;
    for (int i = 0; i < count; ++i) {
        const float d = qAbs(m_radioMarkers[i] - m_frequency);
        if (d < bestDist) {
            bestDist = d;
            current = i;
        }
    }
    if (bestDist > 0.18f)
        current = -1;

    QFontMetrics fm(QFont(QStringLiteral("Segoe UI"), 8));
    for (int i = 0; i < visible; ++i) {
        const int idx = m_radioScroll + i;
        if (idx >= count)
            break;
        const QRectF row(list.left() + 2, list.top() + i * rowH, list.width() - 4, rowH - 1);
        const bool cur = (idx == current);
        const bool hover = (m_hover == QStringLiteral("radio:%1").arg(idx));
        if (cur)
            p.fillRect(row, QColor(255, 140, 40, 45));
        else if (hover)
            p.fillRect(row, QColor(255, 255, 255, 18));

        const QString freq = QStringLiteral("%1").arg(m_radioMarkers[idx], 0, 'f', 1);
        PaintKit::drawLabel(p, QRectF(row.left() + 4, row.top(), 46, row.height()),
                            freq, 8, true,
                            cur ? QColor(255, 170, 70) : QColor(140, 160, 190),
                            Qt::AlignLeft | Qt::AlignVCenter);

        QString name = (idx < m_radioStationNames.size()) ? m_radioStationNames[idx]
                                                          : QStringLiteral("电台 %1").arg(idx + 1);
        name = fm.elidedText(name, Qt::ElideRight, int(row.width() - 58));
        PaintKit::drawLabel(p, QRectF(row.left() + 52, row.top(), row.width() - 56, row.height()),
                            name, 8, cur,
                            cur ? QColor(255, 200, 120) : QColor(200, 200, 205),
                            Qt::AlignLeft | Qt::AlignVCenter);
        m_hit[QStringLiteral("radio:%1").arg(idx)] = row;
    }
}

void CassetteDeckWidget::drawLyricsPage(QPainter &p, const QRectF &rect)
{
    m_lyricsViewport = rect;
    PaintKit::fillBeveledRect(p, rect, QColor(8, 8, 10), 1.5, 2, false);
    if (m_lyrics.isEmpty()) {
        PaintKit::drawLabel(p, rect, QStringLiteral("暂无歌词 · 可放置同名 .lrc"), 8, true, QColor(90, 90, 96));
        return;
    }
    const int cur = currentLyricIndex();
    const qreal rowH = 20;
    const int visible = qMax(1, int(rect.height() / rowH));
    int start = qMax(0, cur - visible / 2);
    start = qMin(start, qMax(0, m_lyrics.size() - visible));
    for (int i = 0; i < visible; ++i) {
        const int idx = start + i;
        if (idx >= m_lyrics.size())
            break;
        const QRectF row(rect.left() + 6, rect.top() + i * rowH, rect.width() - 12, rowH);
        const bool on = (idx == cur);
        p.setFont(QFont(QStringLiteral("Segoe UI"), on ? 9 : 8, on ? QFont::Bold : QFont::Normal));
        p.setPen(on ? QColor(255, 180, 80) : QColor(140, 140, 146));
        p.drawText(row, Qt::AlignHCenter | Qt::AlignVCenter,
                   QFontMetrics(p.font()).elidedText(m_lyrics[idx].text, Qt::ElideRight, int(row.width())));
    }
}

void CassetteDeckWidget::drawReel(QPainter &p, const QPointF &c, qreal rad, float angle, float fill)
{
    const float pack = PaintKit::clamp01(qMax(0.10f, fill));
    const qreal outer = rad * (0.42 + 0.55 * pack);

    // 透明卷盘法兰（略大于磁带卷）
    QRadialGradient flange(c - QPointF(rad * 0.2, rad * 0.25), rad * 1.15);
    flange.setColorAt(0.0, QColor(180, 185, 190, 40));
    flange.setColorAt(0.55, QColor(40, 44, 50, 55));
    flange.setColorAt(1.0, QColor(8, 10, 12, 90));
    p.setBrush(flange);
    p.setPen(QPen(QColor(120, 125, 130, 70), 1.1));
    p.drawEllipse(c, rad, rad);

    // 磁带卷：棕褐色磁粉，带同心圈
    QRadialGradient tape(c, outer);
    tape.setColorAt(0.0, QColor(95, 62, 34));
    tape.setColorAt(0.35, QColor(62, 40, 22));
    tape.setColorAt(0.75, QColor(38, 24, 12));
    tape.setColorAt(1.0, QColor(16, 10, 6));
    p.setBrush(tape);
    p.setPen(QPen(QColor(8, 5, 3), 0.9));
    p.drawEllipse(c, outer, outer);
    p.setPen(QPen(QColor(120, 80, 40, 35), 0.7));
    for (int i = 1; i <= 4; ++i) {
        const qreal r = outer * (0.35 + 0.14 * i);
        if (r < outer)
            p.drawEllipse(c, r, r);
    }

    // 六齿花键轴芯
    const qreal hub = rad * 0.38;
    p.save();
    QPainterPath clip;
    clip.addEllipse(c, hub, hub);
    p.setClipPath(clip);
    p.drawPixmap(QRectF(c.x() - hub, c.y() - hub, hub * 2, hub * 2).toRect(),
                 PaintKit::brushedMetal(int(hub * 2) + 2, int(hub * 2) + 2, 4));
    p.restore();

    p.setPen(QPen(QColor(20, 20, 22), 1.4));
    for (int i = 0; i < 6; ++i) {
        const qreal a = qDegreesToRadians(angle + i * 60.0);
        const QPointF tip(c.x() + qCos(a) * hub * 0.86, c.y() + qSin(a) * hub * 0.86);
        p.drawLine(c, tip);
        // 齿端加粗一点
        p.setBrush(QColor(55, 55, 58));
        p.setPen(Qt::NoPen);
        p.drawEllipse(tip, hub * 0.10, hub * 0.10);
        p.setPen(QPen(QColor(20, 20, 22), 1.4));
    }
    p.setBrush(QColor(18, 18, 20));
    p.setPen(QPen(QColor(90, 90, 94), 0.8));
    p.drawEllipse(c, hub * 0.22, hub * 0.22);
    p.setBrush(QColor(8, 8, 10));
    p.setPen(Qt::NoPen);
    p.drawEllipse(c, hub * 0.10, hub * 0.10);
}

void CassetteDeckWidget::drawTransportModule(QPainter &p, const QRectF &rect)
{
    p.save();
    p.setClipRect(rect);
    const QRectF face = rect.adjusted(6, 3, -6, -3);
    PaintKit::fillBeveledRect(p, face, QColor(28, 28, 32), 2, 3, true);

    // 两侧接口字样，中间留给铭牌
    PaintKit::drawLabel(p, QRectF(face.left() + 10, face.top(), 120, face.height()),
                        QStringLiteral("PHONES · MIC"), 5, false, QColor(110, 110, 114),
                        Qt::AlignLeft | Qt::AlignVCenter);
    PaintKit::drawLabel(p, QRectF(face.right() - 90, face.top(), 80, face.height()),
                        QStringLiteral("LINE IN"), 5, false, QColor(110, 110, 114),
                        Qt::AlignRight | Qt::AlignVCenter);

    // 机头最下方居中铭牌
    {
        const QRectF plate(face.center().x() - 70, face.top() + 1, 140, face.height() - 2);
        PaintKit::drawLabel(p, plate.translated(0.8, 0.8), QStringLiteral("拾音盒子"), 9, true,
                            QColor(0, 0, 0, 150), Qt::AlignCenter, 1.0);
        PaintKit::drawLabel(p, plate, QStringLiteral("拾音盒子"), 9, true,
                            m_theme.plateGold, Qt::AlignCenter, 1.0);
    }
    p.restore();
}

void CassetteDeckWidget::flatKey(QPainter &p, const QRectF &rect, const QString &title,
                                 const QString &key, bool lit, bool hasLed)
{
    const bool pressed = m_pressed == key;
    const bool hover = m_hover == key;
    QColor face = hover ? m_theme.chassisMid.lighter(118) : m_theme.chassisMid;
    const QRectF r = rect.adjusted(0, pressed ? 1 : 0, 0, pressed ? 1 : 0);
    PaintKit::fillBeveledRect(p, r, face, 2, 3, !pressed);

    // 指示灯与文字分区，避免红点压住首字母
    const bool showLed = hasLed || lit;
    const qreal ledPad = showLed ? 12.0 : 0.0;
    const QRectF textR = r.adjusted(ledPad + 1, 0, -2, 0);
    const int fontPx = (title.size() >= 8 && textR.width() < 52) ? 5
                     : (title.size() >= 6 && textR.width() < 56) ? 6 : 7;
    PaintKit::drawLabel(p, textR, title, fontPx, true,
                        lit ? m_theme.labelHot : m_theme.label);
    if (showLed) {
        PaintKit::drawLed(p, QPointF(r.left() + 6, r.center().y()), lit,
                          lit ? m_theme.ledWarm : m_theme.chassisLo, lit ? 1.9 : 1.55);
    }
    m_hit[key] = rect;
}

void CassetteDeckWidget::transportKey(QPainter &p, const QRectF &rect, PaintKit::TransportIcon icon,
                                      const QString &key, bool lit, bool enabled)
{
    const bool pressed = enabled && m_pressed == key;
    const bool hover = enabled && m_hover == key;
    QColor face = enabled ? QColor(52, 52, 56) : QColor(28, 28, 30);
    if (hover)
        face = QColor(66, 66, 72);
    if (lit)
        face = QColor(42, 36, 28);
    const QRectF r = rect.adjusted(0, pressed ? 1.5 : 0, 0, pressed ? 1.5 : 0);
    PaintKit::fillBeveledRect(p, r, face, 1.8, 3.2, enabled && !pressed);
    // 机械键顶面刷纹
    if (enabled) {
        p.setOpacity(0.22);
        p.drawPixmap(r.adjusted(1, 1, -1, -1).toRect(),
                     PaintKit::brushedMetal(qMax(4, int(r.width())), qMax(4, int(r.height())), 7));
        p.setOpacity(1.0);
        p.setPen(QPen(QColor(255, 255, 255, pressed ? 18 : 48), 1));
        p.drawLine(r.left() + 2, r.top() + 1.2, r.right() - 2, r.top() + 1.2);
        p.setPen(QPen(QColor(0, 0, 0, 70), 1));
        p.drawLine(r.left() + 2, r.bottom() - 1.2, r.right() - 2, r.bottom() - 1.2);
    }
    if (lit) {
        QRadialGradient glow(r.center(), r.height() * 0.7);
        glow.setColorAt(0.0, QColor(255, 140, 40, 55));
        glow.setColorAt(1.0, QColor(255, 140, 40, 0));
        p.setBrush(glow);
        p.setPen(Qt::NoPen);
        p.drawEllipse(r.center(), r.width() * 0.35, r.height() * 0.35);
    }
    const QColor iconColor = lit ? QColor(255, 175, 70)
                                 : (enabled ? QColor(232, 232, 236) : QColor(72, 72, 76));
    PaintKit::drawTransportIcon(p, r, icon, iconColor);
    // 始终登记热区：禁用态点击也能走到上层，给出「未装带」提示，而不是完全无响应
    m_hit[key] = rect;
}

QString CassetteDeckWidget::hitTest(const QPointF &pos) const
{
    // 重叠时取面积最小的命中区，避免大热区抢走 PLAY 等小键
    QString best;
    qreal bestArea = std::numeric_limits<qreal>::max();
    for (auto it = m_hit.constBegin(); it != m_hit.constEnd(); ++it) {
        if (!it.value().contains(pos))
            continue;
        const qreal area = it.value().width() * it.value().height();
        if (area < bestArea) {
            bestArea = area;
            best = it.key();
        }
    }
    if (!best.isEmpty())
        return best;
    if (m_progressRect.contains(pos))
        return QStringLiteral("seek");
    return {};
}

void CassetteDeckWidget::mousePressEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton)
        return;
    const QPointF pos = event->position();
    const QString key = hitTest(pos);
    if (key == QLatin1String("seek")) {
        emit seekRequested(PaintKit::clamp01(float((pos.x() - m_progressRect.left()) / m_progressRect.width())));
        return;
    }
    if (key == QLatin1String("volume")) {
        m_dragVol = true;
        setVolumeFromPos(pos);
        return;
    }
    if (key == QLatin1String("amp:mic") || key == QLatin1String("amp:echo")
        || key == QLatin1String("amp:bass") || key == QLatin1String("amp:mid")
        || key == QLatin1String("amp:treble") || key == QLatin1String("amp:balance")) {
        m_dragSlider = key;
        setSliderFromPos(key, pos);
        return;
    }
    if (key == QLatin1String("radio:dial") || key == QLatin1String("radio:tune")) {
        m_dragTune = true;
        m_dragTuneKnob = (key == QLatin1String("radio:tune"));
        setFrequencyFromPos(pos);
        return;
    }
    if (!key.isEmpty()) {
        m_pressed = key;
        update();
    }
}

void CassetteDeckWidget::mouseMoveEvent(QMouseEvent *event)
{
    const QPointF pos = event->position();
    if (m_dragVol) {
        setVolumeFromPos(pos);
        return;
    }
    if (!m_dragSlider.isEmpty()) {
        setSliderFromPos(m_dragSlider, pos);
        return;
    }
    if (m_dragTune) {
        setFrequencyFromPos(pos);
        return;
    }
    const QString key = hitTest(pos);
    if (key != m_hover) {
        m_hover = key;
        update();
    }
    setCursor(key.isEmpty() ? Qt::ArrowCursor : Qt::PointingHandCursor);
}

void CassetteDeckWidget::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton)
        return;
    if (m_dragVol) {
        m_dragVol = false;
        return;
    }
    if (!m_dragSlider.isEmpty()) {
        m_dragSlider.clear();
        return;
    }
    if (m_dragTune) {
        m_dragTune = false;
        m_dragTuneKnob = false;
        return;
    }
    const QString key = m_pressed;
    m_pressed.clear();
    update();
    // 小运控键松开时允许轻微偏移，仍按按下时的键触发
    if (key.isEmpty())
        return;
    if (key.startsWith(QLatin1String("preset:"))) {
        m_preset = key.mid(7);
        // 音效预设联动三段均衡
        if (m_preset == QLatin1String("ROCK")) {
            m_bass = 0.72f; m_mid = 0.55f; m_treble = 0.68f; m_megaBass = true;
        } else if (m_preset == QLatin1String("POPS")) {
            m_bass = 0.58f; m_mid = 0.62f; m_treble = 0.62f; m_megaBass = false;
        } else if (m_preset == QLatin1String("CLASSIC")) {
            m_bass = 0.42f; m_mid = 0.50f; m_treble = 0.55f; m_megaBass = false;
        } else if (m_preset == QLatin1String("JAZZ")) {
            m_bass = 0.50f; m_mid = 0.58f; m_treble = 0.48f; m_megaBass = false;
        } else if (m_preset == QLatin1String("FLAT")) {
            m_bass = 0.50f; m_mid = 0.50f; m_treble = 0.50f; m_megaBass = false;
        } else if (m_preset == QLatin1String("VOCAL")) {
            m_bass = 0.38f; m_mid = 0.72f; m_treble = 0.58f; m_megaBass = false;
        } else { // DISCO
            m_bass = 0.78f; m_mid = 0.48f; m_treble = 0.60f; m_megaBass = true;
        }
        emitTone();
        emit megaBassToggled(m_megaBass);
        update();
        return;
    }
    if (key == QLatin1String("amp:dolby")) {
        m_dolby = !m_dolby;
        emit dolbyToggled(m_dolby);
        update();
        return;
    }
    if (key == QLatin1String("amp:megabass")) {
        m_megaBass = !m_megaBass;
        emit megaBassToggled(m_megaBass);
        update();
        return;
    }
    if (key == QLatin1String("amp:loudness")) {
        m_loudness = !m_loudness;
        emit loudnessToggled(m_loudness);
        update();
        return;
    }
    if (key == QLatin1String("amp:mute")) {
        m_mute = !m_mute;
        emit muteToggled(m_mute);
        update();
        return;
    }
    if (key == QLatin1String("amp:surround")) {
        m_surround = !m_surround;
        update();
        return;
    }
    if (key == QLatin1String("amp:wide")) {
        m_stereoWide = !m_stereoWide;
        update();
        return;
    }
    if (key == QLatin1String("amp:boost")) {
        m_dynBoost = !m_dynBoost;
        if (m_dynBoost && !m_loudness) {
            m_loudness = true;
            emit loudnessToggled(true);
        }
        update();
        return;
    }
    if (key == QLatin1String("amp:peak")) {
        m_peakHold = !m_peakHold;
        update();
        return;
    }
    if (key == QLatin1String("amp:viz") || key.startsWith(QLatin1String("viz:"))) {
        cycleVizMode();
        return;
    }
    if (key == QLatin1String("amp:sleep")) {
        cycleSleepTimer();
        return;
    }
    if (key == QLatin1String("mode:single")
        || key == QLatin1String("mode:random")
        || key == QLatin1String("mode:all")) {
        PlayMode next = PlayMode::AllLoop;
        if (key == QLatin1String("mode:single"))
            next = PlayMode::SingleLoop;
        else if (key == QLatin1String("mode:random"))
            next = PlayMode::Random;
        if (m_playMode != next) {
            m_playMode = next;
            emit playModeChanged(m_playMode);
            update();
        }
        return;
    }

    if (key.startsWith(QLatin1String("tab:"))) {
        const int idx = key.mid(4).toInt();
        if (idx >= 0 && idx <= 3) {
            m_mediaTab = MediaTab(idx);
            update();
        }
        return;
    }
    if (key.startsWith(QLatin1String("list:"))) {
        const int idx = key.mid(5).toInt();
        if (idx >= 0 && idx < m_playlistTitles.size())
            emit trackSelected(idx);
        return;
    }
    {
        bool ok = false;
        const int idx = key.startsWith(QLatin1String("radio:")) ? key.mid(6).toInt(&ok) : -1;
        if (ok && idx >= 0 && idx < m_radioMarkers.size()) {
            emit radioStationSelected(idx);
            return;
        }
    }

    auto fireDeck = [&](const QString &action) {
        if (action == QLatin1String("eject") || action == QLatin1String("open"))
            emit openRequested();
        else if (action == QLatin1String("play"))
            emit playPressed();
        else if (action == QLatin1String("pause"))
            emit pausePressed();
        else if (action == QLatin1String("stop"))
            emit stopPressed();
        else if (action == QLatin1String("prev") || action == QLatin1String("rew"))
            emit rewindPressed();
        else if (action == QLatin1String("next") || action == QLatin1String("ff"))
            emit forwardPressed();
    };

    if (key.startsWith(QLatin1String("a:"))) {
        fireDeck(key.mid(2));
        return;
    }
    if (key == QLatin1String("radio:power")) {
        emit radioPowerToggled(!m_radioPower);
        return;
    }
    if (key == QLatin1String("radio:region")) {
        emit radioRegionPressed();
        return;
    }
    if (key == QLatin1String("radio:prev")) {
        emit radioSeekRequested(-1);
        return;
    }
    if (key == QLatin1String("radio:next")) {
        emit radioSeekRequested(+1);
        return;
    }

    if (key == QLatin1String("open") || key == QLatin1String("eject"))
        emit openRequested();
    else if (key == QLatin1String("power")) {
        if (m_playing)
            emit stopPressed();
        else
            emit playPressed();
    }
}

void CassetteDeckWidget::leaveEvent(QEvent *)
{
    m_hover.clear();
    m_pressed.clear();
    m_dragVol = false;
    m_dragSlider.clear();
    m_dragTune = false;
    m_dragTuneKnob = false;
    update();
}

void CassetteDeckWidget::wheelEvent(QWheelEvent *event)
{
    if (event->angleDelta().y() == 0)
        return;
    const QPointF pos = event->position();
    if (m_dialRect.contains(pos) || m_hit.value(QStringLiteral("radio:tune")).contains(pos)) {
        const float step = event->angleDelta().y() > 0 ? 0.1f : -0.1f;
        m_frequency = clampFrequency(m_frequency + step);
        emit frequencyChanged(m_frequency);
        update();
        return;
    }
    if (m_mediaTab == MediaTab::List && m_listViewport.contains(pos) && !m_playlistTitles.isEmpty()) {
        m_listScroll += (event->angleDelta().y() > 0 ? -1 : 1);
        m_listScroll = qBound(0, m_listScroll, qMax(0, m_playlistTitles.size() - 1));
        update();
        return;
    }
    if (m_mediaTab == MediaTab::Radio && m_radioViewport.contains(pos) && !m_radioMarkers.isEmpty()) {
        m_radioScroll += (event->angleDelta().y() > 0 ? -1 : 1);
        m_radioScroll = qBound(0, m_radioScroll, qMax(0, m_radioMarkers.size() - 1));
        update();
        return;
    }
    m_volume = PaintKit::clamp01(m_volume + (event->angleDelta().y() > 0 ? 0.04f : -0.04f));
    emit volumeChanged(m_volume);
    update();
}

void CassetteDeckWidget::setVolumeFromPos(const QPointF &pos)
{
    const qreal dx = pos.x() - m_knobCenter.x();
    const qreal dy = pos.y() - m_knobCenter.y();
    qreal ang = qRadiansToDegrees(qAtan2(dy, dx));
    qreal rel = std::fmod(ang + 135.0 + 360.0, 360.0);
    float value = 0.f;
    if (rel > 270.0)
        value = (rel < 315.0) ? 0.f : 1.f;
    else
        value = float(rel / 270.0);
    m_volume = PaintKit::clamp01(value);
    if (m_mute) {
        m_mute = false;
        emit muteToggled(false);
    }
    emit volumeChanged(m_volume);
    update();
}

void CassetteDeckWidget::emitTone()
{
    emit toneChanged(m_bass, m_mid, m_treble, m_balance);
}

void CassetteDeckWidget::cycleSleepTimer()
{
    static const int opts[] = {0, 15, 30, 60, 90};
    int idx = 0;
    for (int i = 0; i < 5; ++i) {
        if (opts[i] == m_sleepPresetMin) {
            idx = i;
            break;
        }
    }
    idx = (idx + 1) % 5;
    m_sleepPresetMin = opts[idx];
    if (m_sleepPresetMin <= 0) {
        m_sleepTimer->stop();
        m_sleepRemainSec = 0;
        emit sleepFadeChanged(1.f);
        emit sleepRemainingChanged(0);
    } else {
        m_sleepRemainSec = m_sleepPresetMin * 60;
        m_sleepTimer->start();
        emit sleepFadeChanged(1.f);
        emit sleepRemainingChanged(m_sleepRemainSec);
    }
    update();
}

void CassetteDeckWidget::onSleepTick()
{
    if (m_sleepRemainSec <= 0) {
        m_sleepTimer->stop();
        m_sleepPresetMin = 0;
        return;
    }
    --m_sleepRemainSec;
    emit sleepRemainingChanged(m_sleepRemainSec);

    // 最后一分钟渐弱：只改 fade，绝不改写用户音量旋钮
    if (m_sleepRemainSec > 0 && m_sleepRemainSec <= 60 && !m_mute)
        emit sleepFadeChanged(m_sleepRemainSec / 60.f);
    else
        emit sleepFadeChanged(1.f);

    if (m_sleepRemainSec <= 0) {
        m_sleepTimer->stop();
        m_sleepPresetMin = 0;
        emit sleepFadeChanged(1.f);
        emit sleepFinished();
    }
    update();
}

QString CassetteDeckWidget::sleepStatusText() const
{
    if (m_sleepPresetMin <= 0)
        return QStringLiteral("SLEEP");
    const int m = m_sleepRemainSec / 60;
    const int s = m_sleepRemainSec % 60;
    return QStringLiteral("SL %1:%2")
        .arg(m, 2, 10, QChar('0'))
        .arg(s, 2, 10, QChar('0'));
}

QString CassetteDeckWidget::playModeLabel(PlayMode mode) const
{
    switch (mode) {
    case PlayMode::SingleLoop:
        return QStringLiteral("REPEAT 1");
    case PlayMode::Random:
        return QStringLiteral("SHUFFLE");
    case PlayMode::AllLoop:
    default:
        return QStringLiteral("REPEAT ALL");
    }
}

void CassetteDeckWidget::setSliderFromPos(const QString &key, const QPointF &pos)
{
    if (key == QLatin1String("amp:bass") || key == QLatin1String("amp:mid")
        || key == QLatin1String("amp:treble") || key == QLatin1String("amp:balance")) {
        const QRectF track = m_sliderTracks.value(key);
        if (track.height() < 1)
            return;
        const float v = PaintKit::clamp01(float(1.0 - (pos.y() - track.top()) / track.height()));
        if (key == QLatin1String("amp:bass"))
            m_bass = v;
        else if (key == QLatin1String("amp:mid"))
            m_mid = v;
        else if (key == QLatin1String("amp:treble"))
            m_treble = v;
        else
            m_balance = v;
        // 手动调滑块后退出固定预设名，避免灯还亮着旧预设
        if (key != QLatin1String("amp:balance"))
            m_preset.clear();
        emitTone();
        update();
        return;
    }

    // MIC / ECHO：按旋钮圆心角度
    const QRectF hit = m_hit.value(key);
    if (hit.isEmpty())
        return;
    const QPointF c = hit.center();
    const qreal dx = pos.x() - c.x();
    const qreal dy = pos.y() - c.y();
    qreal ang = qRadiansToDegrees(qAtan2(dy, dx));
    qreal rel = std::fmod(ang + 135.0 + 360.0, 360.0);
    float value = 0.f;
    if (rel > 270.0)
        value = (rel < 315.0) ? 0.f : 1.f;
    else
        value = float(rel / 270.0);
    value = PaintKit::clamp01(value);
    if (key == QLatin1String("amp:mic"))
        m_micLevel = value;
    else if (key == QLatin1String("amp:echo"))
        m_echoLevel = value;
    update();
}

void CassetteDeckWidget::setFrequencyFromPos(const QPointF &pos)
{
    float mhz = m_frequency;
    if (m_dragTuneKnob) {
        const qreal dx = pos.x() - m_tuneKnobCenter.x();
        const qreal dy = pos.y() - m_tuneKnobCenter.y();
        qreal ang = qRadiansToDegrees(qAtan2(dy, dx));
        qreal rel = std::fmod(ang + 135.0 + 360.0, 360.0);
        float value = 0.f;
        if (rel > 270.0)
            value = (rel < 315.0) ? 0.f : 1.f;
        else
            value = float(rel / 270.0);
        mhz = m_fmMin + value * (m_fmMax - m_fmMin);
    } else {
        mhz = freqFromDialX(pos.x());
    }
    mhz = std::round(mhz * 10.f) / 10.f;
    mhz = clampFrequency(mhz);
    if (qAbs(mhz - m_frequency) < 0.01f)
        return;
    m_frequency = mhz;
    emit frequencyChanged(m_frequency);
    update();
}
