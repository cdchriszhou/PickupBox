#pragma once

#include <QColor>
#include <QPainter>
#include <QPixmap>
#include <QPointF>
#include <QRectF>
#include <QString>

namespace PaintKit {

inline float clamp01(float v) { return v < 0.f ? 0.f : (v > 1.f ? 1.f : v); }

QPixmap plasticNoise(int w, int h, int seed = 1, int strength = 10);
QPixmap clothMesh(int w, int h, int seed = 7);
QPixmap brushedMetal(int w, int h, int seed = 3);
QPixmap wornScratches(int w, int h, int seed = 13);
void paintWornOverlay(QPainter &p, const QRectF &rect, int seed = 13);

void fillBeveledRect(QPainter &p, const QRectF &rect, const QColor &face,
                     qreal radius = 2.0, qreal depth = 3.0, bool raised = true);
void drawScrew(QPainter &p, const QPointF &c, qreal r = 3.2);
void drawLed(QPainter &p, const QPointF &c, bool on,
             const QColor &color = QColor(255, 36, 28), qreal r = 2.6);
void drawLabel(QPainter &p, const QRectF &rect, const QString &text,
               int size = 7, bool bold = true,
               const QColor &color = QColor(205, 205, 208),
               int align = Qt::AlignCenter, qreal tracking = 0.0);
void drawGlassReflection(QPainter &p, const QRectF &rect);
void drawKnob(QPainter &p, const QPointF &c, qreal radius, float value,
              const QColor &indicator = QColor(230, 40, 35));
QRectF drawRecessedWell(QPainter &p, const QRectF &rect, qreal radius = 3.0);

enum class TransportIcon {
    Rewind, Play, Pause, Stop, Forward, Eject, Prev, Next
};

void drawTransportIcon(QPainter &p, const QRectF &rect, TransportIcon icon,
                       const QColor &color);

} // namespace PaintKit
