#include "PaintKit.h"

#include <QtMath>
#include <QFont>
#include <QImage>
#include <QLinearGradient>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <QPen>
#include <QHash>
#include <random>

namespace PaintKit {
namespace {

QHash<QString, QPixmap> &cache()
{
    static QHash<QString, QPixmap> c;
    return c;
}

} // namespace

QPixmap plasticNoise(int w, int h, int seed, int strength)
{
    const QString key = QStringLiteral("pn-%1-%2-%3-%4").arg(w).arg(h).arg(seed).arg(strength);
    if (cache().contains(key))
        return cache().value(key);

    QImage img(qMax(1, w / 2), qMax(1, h / 2), QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    std::mt19937 rng(static_cast<unsigned>(seed));
    std::uniform_int_distribution<int> dist(-strength, strength);
    std::uniform_real_distribution<float> chance(0.f, 1.f);
    for (int y = 0; y < img.height(); ++y) {
        for (int x = 0; x < img.width(); ++x) {
            if (chance(rng) > 0.35f)
                continue;
            const int n = dist(rng);
            const int c = qBound(0, 128 + n, 255);
            const int a = qBound(0, 16 + qAbs(n) * 2, 40);
            img.setPixelColor(x, y, QColor(c, c, c, a));
        }
    }
    QPixmap pm = QPixmap::fromImage(img).scaled(w, h, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    cache().insert(key, pm);
    return pm;
}

QPixmap clothMesh(int w, int h, int seed)
{
    const QString key = QStringLiteral("cm-%1-%2-%3").arg(w).arg(h).arg(seed);
    if (cache().contains(key))
        return cache().value(key);

    const int sw = qBound(64, w, 180);
    const int sh = qBound(64, h, 520);
    QImage img(sw, sh, QImage::Format_RGB32);
    std::mt19937 rng(static_cast<unsigned>(seed));
    std::uniform_int_distribution<int> jitter(-3, 3);
    for (int y = 0; y < sh; ++y) {
        for (int x = 0; x < sw; ++x) {
            const float fx = x / 8.f;
            const float fy = y / 8.f;
            float v = 22.f + 7.f * qSin(fx * 7.2f) * qCos(fy * 4.4f)
                      + 5.f * qSin((fx + fy) * 5.2f);
            if ((x + y * 2) % 3 == 0)
                v += 4.f;
            if ((x * 2 + y) % 5 == 0)
                v -= 5.f;
            v += jitter(rng);
            const int g = qBound(8, int(v), 50);
            img.setPixelColor(x, y, QColor(g, g, g + 1));
        }
    }
    QPixmap pm = QPixmap::fromImage(img).scaled(w, h, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    cache().insert(key, pm);
    return pm;
}

QPixmap brushedMetal(int w, int h, int seed)
{
    const QString key = QStringLiteral("bm-%1-%2-%3").arg(w).arg(h).arg(seed);
    if (cache().contains(key))
        return cache().value(key);

    QImage img(qMax(1, w), qMax(1, h), QImage::Format_RGB32);
    std::mt19937 rng(static_cast<unsigned>(seed));
    std::uniform_int_distribution<int> rowJ(-18, 18);
    std::uniform_int_distribution<int> pixJ(-4, 4);
    for (int y = 0; y < img.height(); ++y) {
        const int row = 90 + rowJ(rng);
        for (int x = 0; x < img.width(); ++x) {
            const int v = qBound(40, row + int(6 * qSin(x * 0.35 + seed)) + pixJ(rng), 170);
            img.setPixelColor(x, y, QColor(v, v, v + 2));
        }
    }
    QPixmap pm = QPixmap::fromImage(img);
    cache().insert(key, pm);
    return pm;
}

QPixmap wornScratches(int w, int h, int seed)
{
    const QString key = QStringLiteral("ws-%1-%2-%3").arg(w).arg(h).arg(seed);
    if (cache().contains(key))
        return cache().value(key);

    QImage img(qMax(1, w), qMax(1, h), QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter gp(&img);
    gp.setRenderHint(QPainter::Antialiasing, true);
    std::mt19937 rng(static_cast<unsigned>(seed * 97 + 11));
    std::uniform_real_distribution<qreal> ux(0.0, 1.0);
    std::uniform_real_distribution<qreal> uy(0.0, 1.0);
    const int n = qBound(18, (w * h) / 1400, 55);
    for (int i = 0; i < n; ++i) {
        const QPointF a(ux(rng) * w, uy(rng) * h);
        const QPointF b(a.x() + (ux(rng) - 0.5) * w * 0.35,
                        a.y() + (uy(rng) - 0.48) * h * 0.08);
        const int aAlpha = 10 + int(ux(rng) * 28);
        gp.setPen(QPen(QColor(255, 245, 220, aAlpha), 0.7 + ux(rng) * 0.8));
        gp.drawLine(a, b);
        if (ux(rng) > 0.7) {
            gp.setPen(QPen(QColor(0, 0, 0, 12 + int(ux(rng) * 20)), 0.6));
            gp.drawLine(a + QPointF(0.6, 0.6), b + QPointF(0.6, 0.6));
        }
    }
    // 边角磨白
    for (int i = 0; i < 10; ++i) {
        const qreal t = ux(rng);
        const QPointF c(t < 0.5 ? ux(rng) * w * 0.18 : w - ux(rng) * w * 0.18,
                        uy(rng) * h);
        gp.setBrush(QColor(220, 210, 190, 8 + int(ux(rng) * 16)));
        gp.setPen(Qt::NoPen);
        gp.drawEllipse(c, 2 + ux(rng) * 5, 1.2 + uy(rng) * 3);
    }
    gp.end();
    QPixmap pm = QPixmap::fromImage(img);
    cache().insert(key, pm);
    return pm;
}

void paintWornOverlay(QPainter &p, const QRectF &rect, int seed)
{
    if (rect.width() < 4 || rect.height() < 4)
        return;
    p.save();
    p.setOpacity(0.55);
    p.drawPixmap(rect.toRect(), wornScratches(int(rect.width()), int(rect.height()), seed));
    p.setOpacity(1.0);
    // 岁月发黄的边缘
    QLinearGradient age(rect.topLeft(), rect.bottomRight());
    age.setColorAt(0.0, QColor(180, 140, 70, 18));
    age.setColorAt(0.45, QColor(0, 0, 0, 0));
    age.setColorAt(1.0, QColor(40, 30, 10, 22));
    p.fillRect(rect, age);
    p.restore();
}

void fillBeveledRect(QPainter &p, const QRectF &rect, const QColor &face,
                     qreal radius, qreal depth, bool raised)
{
    QPainterPath path;
    path.addRoundedRect(rect, radius, radius);
    QLinearGradient g(rect.topLeft(), rect.bottomLeft());
    if (raised) {
        g.setColorAt(0.0, face.lighter(118));
        g.setColorAt(0.08, face);
        g.setColorAt(0.92, face.darker(108));
        g.setColorAt(1.0, face.darker(125));
    } else {
        g.setColorAt(0.0, face.darker(130));
        g.setColorAt(0.15, face.darker(110));
        g.setColorAt(0.85, face);
        g.setColorAt(1.0, face.lighter(105));
    }
    p.fillPath(path, g);
    p.setPen(QPen(QColor(255, 255, 255, raised ? 55 : 20), 1));
    p.drawLine(QPointF(rect.left() + radius, rect.top() + 0.8),
               QPointF(rect.right() - radius, rect.top() + 0.8));
    p.setPen(QPen(QColor(0, 0, 0, raised ? 110 : 160), 1));
    p.drawLine(QPointF(rect.left() + radius, rect.bottom() - 0.8),
               QPointF(rect.right() - radius, rect.bottom() - 0.8));
    QLinearGradient ao(rect.topLeft(), rect.topLeft() + QPointF(0, depth * 4));
    ao.setColorAt(0.0, QColor(0, 0, 0, raised ? 18 : 50));
    ao.setColorAt(1.0, QColor(0, 0, 0, 0));
    p.fillPath(path, ao);
}

void drawScrew(QPainter &p, const QPointF &c, qreal r)
{
    QRadialGradient g(c - QPointF(r * 0.3, r * 0.3), r * 1.4);
    g.setColorAt(0.0, QColor(120, 120, 124));
    g.setColorAt(0.55, QColor(55, 55, 58));
    g.setColorAt(1.0, QColor(20, 20, 22));
    p.setBrush(g);
    p.setPen(QPen(QColor(0, 0, 0, 180), 0.8));
    p.drawEllipse(c, r, r);
    p.setPen(QPen(QColor(15, 15, 16), 1.1));
    p.drawLine(c + QPointF(-r * 0.55, 0), c + QPointF(r * 0.55, 0));
    p.drawLine(c + QPointF(0, -r * 0.55), c + QPointF(0, r * 0.55));
}

void drawLed(QPainter &p, const QPointF &c, bool on, const QColor &color, qreal r)
{
    p.setBrush(QColor(12, 12, 14));
    p.setPen(QPen(QColor(0, 0, 0), 0.8));
    p.drawEllipse(c, r + 1.2, r + 1.2);
    if (on) {
        QRadialGradient glow(c, r * 3.2);
        QColor gc = color;
        gc.setAlpha(90);
        glow.setColorAt(0.0, gc);
        glow.setColorAt(1.0, QColor(0, 0, 0, 0));
        p.setBrush(glow);
        p.setPen(Qt::NoPen);
        p.drawEllipse(c, r * 3.0, r * 3.0);
        QRadialGradient core(c - QPointF(r * 0.25, r * 0.25), r);
        core.setColorAt(0.0, QColor(255, 220, 200));
        core.setColorAt(0.35, color);
        core.setColorAt(1.0, color.darker(160));
        p.setBrush(core);
        p.drawEllipse(c, r, r);
    } else {
        p.setBrush(color.darker(280));
        p.setPen(QPen(QColor(0, 0, 0), 0.6));
        p.drawEllipse(c, r, r);
    }
}

void drawLabel(QPainter &p, const QRectF &rect, const QString &text,
               int size, bool bold, const QColor &color, int align, qreal tracking)
{
    QFont font(QStringLiteral("Segoe UI"), size, bold ? QFont::Bold : QFont::Normal);
    if (tracking > 0)
        font.setLetterSpacing(QFont::AbsoluteSpacing, tracking);
    p.setFont(font);
    p.setPen(color);
    p.drawText(rect, align, text);
}

void drawGlassReflection(QPainter &p, const QRectF &rect)
{
    QLinearGradient gloss(rect.topLeft(), rect.bottomRight());
    gloss.setColorAt(0.0, QColor(255, 255, 255, 28));
    gloss.setColorAt(0.22, QColor(255, 255, 255, 8));
    gloss.setColorAt(0.45, QColor(255, 255, 255, 0));
    gloss.setColorAt(0.7, QColor(255, 255, 255, 0));
    gloss.setColorAt(1.0, QColor(255, 255, 255, 12));
    p.fillRect(rect, gloss);
}

void drawKnob(QPainter &p, const QPointF &c, qreal radius, float value, const QColor &indicator)
{
    value = clamp01(value);
    QRadialGradient sh(c + QPointF(1.5, 3.0), radius * 1.35);
    sh.setColorAt(0.0, QColor(0, 0, 0, 100));
    sh.setColorAt(1.0, QColor(0, 0, 0, 0));
    p.setBrush(sh);
    p.setPen(Qt::NoPen);
    p.drawEllipse(c + QPointF(1.5, 2.5), radius * 1.05, radius * 1.05);

    QRadialGradient skirt(c - QPointF(radius * 0.2, radius * 0.35), radius * 1.3);
    skirt.setColorAt(0.0, QColor(64, 64, 68));
    skirt.setColorAt(0.45, QColor(32, 32, 36));
    skirt.setColorAt(1.0, QColor(12, 12, 14));
    p.setBrush(skirt);
    p.setPen(QPen(QColor(0, 0, 0, 200), 1));
    p.drawEllipse(c, radius, radius);

    p.setPen(QPen(QColor(0, 0, 0, 90), 1));
    for (int i = 0; i < 24; ++i) {
        const qreal a = qDegreesToRadians(i * 15.0);
        p.drawLine(QPointF(c.x() + qCos(a) * radius * 0.78, c.y() + qSin(a) * radius * 0.78),
                   QPointF(c.x() + qCos(a) * radius * 0.96, c.y() + qSin(a) * radius * 0.96));
    }

    const qreal capR = radius * 0.72;
    const QPixmap metal = brushedMetal(int(capR * 2) + 2, int(capR * 2) + 2);
    p.save();
    QPainterPath clip;
    clip.addEllipse(c, capR, capR);
    p.setClipPath(clip);
    p.drawPixmap(QRectF(c.x() - capR, c.y() - capR, capR * 2, capR * 2).toRect(), metal);
    QRadialGradient dark(c, capR);
    dark.setColorAt(0.0, QColor(255, 255, 255, 35));
    dark.setColorAt(0.55, QColor(0, 0, 0, 0));
    dark.setColorAt(1.0, QColor(0, 0, 0, 90));
    p.setBrush(dark);
    p.setPen(Qt::NoPen);
    p.drawEllipse(c, capR, capR);
    p.restore();

    p.setPen(QPen(QColor(160, 160, 165), 1));
    p.setBrush(Qt::NoBrush);
    p.drawEllipse(c, capR, capR);

    const qreal ang = qDegreesToRadians(-135.0 + value * 270.0);
    const QPointF tip(c.x() + qCos(ang) * capR * 0.82, c.y() + qSin(ang) * capR * 0.82);
    p.setPen(QPen(QColor(20, 20, 22), 3.2));
    p.drawLine(c, tip);
    p.setPen(QPen(indicator, 1.8));
    p.drawLine(c, tip);
    p.setBrush(indicator);
    p.setPen(Qt::NoPen);
    p.drawEllipse(tip, 2.1, 2.1);

    QRadialGradient riv(c - QPointF(1, 1), radius * 0.2);
    riv.setColorAt(0.0, QColor(90, 90, 94));
    riv.setColorAt(1.0, QColor(25, 25, 28));
    p.setBrush(riv);
    p.drawEllipse(c, radius * 0.14, radius * 0.14);

    p.setPen(QPen(QColor(140, 140, 145), 1));
    for (int i = 0; i < 11; ++i) {
        const qreal a = qDegreesToRadians(-135.0 + i * 27.0);
        const bool lng = (i % 5 == 0);
        const qreal r0 = radius + 2.5;
        const qreal r1 = radius + (lng ? 7.5 : 5.0);
        p.drawLine(QPointF(c.x() + qCos(a) * r0, c.y() + qSin(a) * r0),
                   QPointF(c.x() + qCos(a) * r1, c.y() + qSin(a) * r1));
    }
}

QRectF drawRecessedWell(QPainter &p, const QRectF &rect, qreal radius)
{
    fillBeveledRect(p, rect, QColor(38, 38, 42), radius, 3.0, true);
    const QRectF inner = rect.adjusted(3, 3, -3, -3);
    fillBeveledRect(p, inner, QColor(14, 14, 16), qMax(0.5, radius - 1), 6.0, false);
    const QRectF pit = inner.adjusted(2, 2, -2, -2);
    QLinearGradient g(pit.topLeft(), pit.bottomLeft());
    g.setColorAt(0.0, QColor(6, 6, 8));
    g.setColorAt(1.0, QColor(10, 10, 12));
    QPainterPath path;
    path.addRoundedRect(pit, 2, 2);
    p.fillPath(path, g);
    return pit;
}

namespace {

QPainterPath triangle(const QPointF &tip, const QPointF &a, const QPointF &b)
{
    QPainterPath path;
    path.moveTo(tip);
    path.lineTo(a);
    path.lineTo(b);
    path.closeSubpath();
    return path;
}

void paintIconShape(QPainter &p, const QPainterPath &path, const QColor &color)
{
    QLinearGradient g(path.boundingRect().topLeft(), path.boundingRect().bottomLeft());
    g.setColorAt(0.0, color.lighter(118));
    g.setColorAt(0.45, color);
    g.setColorAt(1.0, color.darker(125));
    p.setBrush(g);
    p.setPen(QPen(color.darker(160), 0.6));
    p.drawPath(path);
    // soft top specular
    p.setPen(QPen(QColor(255, 255, 255, 50), 0.8));
    const QRectF b = path.boundingRect();
    p.drawLine(QPointF(b.left() + 1, b.top() + 1), QPointF(b.right() - 1, b.top() + 1));
}

} // namespace

void drawTransportIcon(QPainter &p, const QRectF &rect, TransportIcon icon, const QColor &color)
{
    const QRectF r = rect.adjusted(rect.width() * 0.22, rect.height() * 0.22,
                                   -rect.width() * 0.22, -rect.height() * 0.22);
    const qreal cx = r.center().x();
    const qreal cy = r.center().y();
    const qreal w = r.width();
    const qreal h = r.height();

    p.save();
    p.setRenderHint(QPainter::Antialiasing, true);

    switch (icon) {
    case TransportIcon::Play: {
        const qreal ox = w * 0.08;
        paintIconShape(p,
                       triangle(QPointF(cx - w * 0.28 + ox, cy - h * 0.42),
                                QPointF(cx - w * 0.28 + ox, cy + h * 0.42),
                                QPointF(cx + w * 0.42 + ox, cy)),
                       color);
        break;
    }
    case TransportIcon::Pause: {
        const qreal bw = w * 0.22;
        const qreal gap = w * 0.16;
        QPainterPath left;
        left.addRoundedRect(QRectF(cx - gap * 0.5 - bw, cy - h * 0.40, bw, h * 0.80), 1.2, 1.2);
        QPainterPath right;
        right.addRoundedRect(QRectF(cx + gap * 0.5, cy - h * 0.40, bw, h * 0.80), 1.2, 1.2);
        paintIconShape(p, left, color);
        paintIconShape(p, right, color);
        break;
    }
    case TransportIcon::Stop: {
        QPainterPath sq;
        const qreal s = qMin(w, h) * 0.72;
        sq.addRoundedRect(QRectF(cx - s * 0.5, cy - s * 0.5, s, s), 1.4, 1.4);
        paintIconShape(p, sq, color);
        break;
    }
    case TransportIcon::Rewind:
    case TransportIcon::Forward: {
        const bool left = (icon == TransportIcon::Rewind);
        const qreal dir = left ? -1.0 : 1.0;
        const qreal tipX = cx + dir * w * 0.42;
        const qreal midX = cx - dir * w * 0.02;
        const qreal backX = cx - dir * w * 0.42;
        paintIconShape(p,
                       triangle(QPointF(tipX, cy),
                                QPointF(midX, cy - h * 0.40),
                                QPointF(midX, cy + h * 0.40)),
                       color);
        paintIconShape(p,
                       triangle(QPointF(midX, cy),
                                QPointF(backX, cy - h * 0.40),
                                QPointF(backX, cy + h * 0.40)),
                       color);
        break;
    }
    case TransportIcon::Eject: {
        QPainterPath tri = triangle(QPointF(cx, cy - h * 0.42),
                                    QPointF(cx - w * 0.40, cy + h * 0.12),
                                    QPointF(cx + w * 0.40, cy + h * 0.12));
        paintIconShape(p, tri, color);
        QPainterPath bar;
        bar.addRoundedRect(QRectF(cx - w * 0.40, cy + h * 0.28, w * 0.80, h * 0.16), 1.0, 1.0);
        paintIconShape(p, bar, color);
        break;
    }
    case TransportIcon::Prev:
    case TransportIcon::Next: {
        // 上一曲 |◀  / 下一曲 ▶|
        const bool left = (icon == TransportIcon::Prev);
        const qreal dir = left ? -1.0 : 1.0;
        const qreal tipX = cx + dir * w * 0.10;
        const qreal baseX = cx - dir * w * 0.38;
        paintIconShape(p,
                       triangle(QPointF(tipX, cy),
                                QPointF(baseX, cy - h * 0.40),
                                QPointF(baseX, cy + h * 0.40)),
                       color);
        QPainterPath bar;
        const qreal bw = qMax(1.6, w * 0.12);
        const qreal bx = left ? (cx - w * 0.48) : (cx + w * 0.48 - bw);
        bar.addRoundedRect(QRectF(bx, cy - h * 0.40, bw, h * 0.80), 0.8, 0.8);
        paintIconShape(p, bar, color);
        break;
    }
    }

    p.restore();
}

} // namespace PaintKit
