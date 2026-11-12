#include "UiTheme.h"

UiTheme UiTheme::make(Id id)
{
    UiTheme t;
    t.id = id;

    switch (id) {
    case Id::SilverStudio:
        t.key = QStringLiteral("silver");
        t.nameZh = QStringLiteral("银灰工作室");
        t.windowBg = QColor(14, 16, 20);
        t.statusBg = QColor(18, 20, 24);
        t.statusFg = QColor(140, 150, 165);
        t.rackTop = QColor(78, 84, 94);
        t.rackMid = QColor(42, 46, 54);
        t.rackBot = QColor(22, 24, 28);
        t.rackEdge = QColor(120, 130, 145);
        t.chassisLo = QColor(28, 30, 36);
        t.chassisMid = QColor(52, 56, 64);
        t.chassisHi = QColor(168, 176, 190);
        t.baffle = QColor(24, 26, 32);
        t.baffleDeep = QColor(12, 14, 18);
        t.plateGold = QColor(190, 200, 220);
        t.screw = QColor(150, 156, 168);
        t.ampFace = QColor(40, 44, 52);
        t.ampWell = QColor(10, 12, 16);
        t.metal = QColor(160, 168, 180);
        t.seam = QColor(90, 98, 112);
        t.accent = QColor(70, 150, 255);
        t.accentHot = QColor(120, 190, 255);
        t.accentDim = QColor(50, 80, 120);
        t.ledWarm = QColor(255, 170, 60);
        t.ledCool = QColor(80, 190, 255);
        t.ledDanger = QColor(255, 70, 70);
        t.label = QColor(210, 218, 230);
        t.labelDim = QColor(120, 130, 145);
        t.labelHot = QColor(150, 200, 255);
        t.vfdGlow = QColor(120, 200, 255);
        t.vizCore = QColor(160, 210, 255);
        t.vizGlow = QColor(60, 140, 255);
        t.menuBg = QColor(24, 28, 34);
        t.menuFg = QColor(220, 226, 235);
        t.menuSel = QColor(48, 70, 110);
        t.menuBar = QColor(18, 20, 26);
        break;

    case Id::WalnutLounge:
        t.key = QStringLiteral("walnut");
        t.nameZh = QStringLiteral("胡桃客厅");
        t.windowBg = QColor(22, 16, 12);
        t.statusBg = QColor(28, 20, 14);
        t.statusFg = QColor(170, 145, 110);
        t.rackTop = QColor(92, 62, 40);
        t.rackMid = QColor(48, 32, 22);
        t.rackBot = QColor(24, 16, 12);
        t.rackEdge = QColor(140, 100, 65);
        t.chassisLo = QColor(36, 24, 16);
        t.chassisMid = QColor(72, 48, 32);
        t.chassisHi = QColor(150, 110, 72);
        t.baffle = QColor(28, 20, 14);
        t.baffleDeep = QColor(14, 10, 8);
        t.plateGold = QColor(220, 185, 120);
        t.screw = QColor(160, 130, 90);
        t.ampFace = QColor(48, 34, 24);
        t.ampWell = QColor(16, 12, 8);
        t.metal = QColor(180, 150, 105);
        t.seam = QColor(110, 80, 50);
        t.accent = QColor(210, 150, 70);
        t.accentHot = QColor(255, 200, 120);
        t.accentDim = QColor(120, 80, 40);
        t.ledWarm = QColor(255, 140, 50);
        t.ledCool = QColor(120, 200, 140);
        t.ledDanger = QColor(230, 70, 50);
        t.label = QColor(230, 210, 175);
        t.labelDim = QColor(150, 125, 95);
        t.labelHot = QColor(255, 210, 140);
        t.vfdGlow = QColor(255, 190, 110);
        t.vizCore = QColor(255, 200, 120);
        t.vizGlow = QColor(220, 120, 40);
        t.menuBg = QColor(36, 26, 18);
        t.menuFg = QColor(235, 220, 190);
        t.menuSel = QColor(90, 60, 35);
        t.menuBar = QColor(28, 20, 14);
        break;

    case Id::NeonPulse:
        t.key = QStringLiteral("neon");
        t.nameZh = QStringLiteral("霓虹脉冲");
        t.windowBg = QColor(6, 6, 12);
        t.statusBg = QColor(8, 8, 16);
        t.statusFg = QColor(140, 120, 180);
        t.rackTop = QColor(36, 28, 55);
        t.rackMid = QColor(16, 12, 28);
        t.rackBot = QColor(6, 6, 12);
        t.rackEdge = QColor(120, 70, 200);
        t.chassisLo = QColor(12, 10, 22);
        t.chassisMid = QColor(28, 22, 48);
        t.chassisHi = QColor(90, 60, 150);
        t.baffle = QColor(10, 10, 18);
        t.baffleDeep = QColor(4, 4, 10);
        t.plateGold = QColor(220, 120, 255);
        t.screw = QColor(120, 100, 160);
        t.ampFace = QColor(18, 14, 32);
        t.ampWell = QColor(6, 6, 14);
        t.metal = QColor(180, 120, 255);
        t.seam = QColor(80, 50, 140);
        t.accent = QColor(0, 230, 210);
        t.accentHot = QColor(255, 70, 200);
        t.accentDim = QColor(40, 100, 110);
        t.ledWarm = QColor(255, 80, 200);
        t.ledCool = QColor(0, 240, 220);
        t.ledDanger = QColor(255, 50, 100);
        t.label = QColor(210, 200, 240);
        t.labelDim = QColor(120, 110, 150);
        t.labelHot = QColor(80, 255, 230);
        t.vfdGlow = QColor(80, 255, 220);
        t.vizCore = QColor(255, 90, 210);
        t.vizGlow = QColor(0, 220, 200);
        t.menuBg = QColor(16, 12, 28);
        t.menuFg = QColor(230, 220, 255);
        t.menuSel = QColor(50, 30, 90);
        t.menuBar = QColor(10, 8, 20);
        break;

    case Id::ClassicAmber:
    default:
        t.key = QStringLiteral("classic");
        t.nameZh = QStringLiteral("经典琥珀");
        t.windowBg = QColor(10, 10, 12);
        t.statusBg = QColor(14, 14, 16);
        t.statusFg = QColor(138, 138, 144);
        t.rackTop = QColor(48, 48, 52);
        t.rackMid = QColor(22, 22, 24);
        t.rackBot = QColor(8, 8, 10);
        t.rackEdge = QColor(70, 70, 74);
        t.chassisLo = QColor(22, 22, 24);
        t.chassisMid = QColor(34, 34, 38);
        t.chassisHi = QColor(46, 46, 50);
        t.baffle = QColor(16, 16, 18);
        t.baffleDeep = QColor(12, 12, 14);
        t.plateGold = QColor(198, 178, 128);
        t.screw = QColor(160, 160, 165);
        t.ampFace = QColor(28, 26, 24);
        t.ampWell = QColor(6, 8, 8);
        t.metal = QColor(180, 170, 140);
        t.seam = QColor(60, 60, 64);
        t.accent = QColor(210, 150, 70);
        t.accentHot = QColor(255, 190, 110);
        t.accentDim = QColor(120, 90, 50);
        t.ledWarm = QColor(255, 36, 28);
        t.ledCool = QColor(80, 180, 255);
        t.ledDanger = QColor(255, 70, 50);
        t.label = QColor(205, 205, 208);
        t.labelDim = QColor(120, 120, 124);
        t.labelHot = QColor(255, 190, 110);
        t.vfdGlow = QColor(255, 170, 70);
        t.vizCore = QColor(255, 190, 90);
        t.vizGlow = QColor(255, 120, 30);
        t.menuBg = QColor(26, 26, 30);
        t.menuFg = QColor(221, 221, 221);
        t.menuSel = QColor(51, 51, 58);
        t.menuBar = QColor(18, 18, 20);
        break;
    }
    return t;
}

QVector<UiTheme> UiTheme::all()
{
    return {
        make(Id::ClassicAmber),
        make(Id::SilverStudio),
        make(Id::WalnutLounge),
        make(Id::NeonPulse),
    };
}

UiTheme::Id UiTheme::idFromKey(const QString &key)
{
    if (key == QLatin1String("silver"))
        return Id::SilverStudio;
    if (key == QLatin1String("walnut"))
        return Id::WalnutLounge;
    if (key == QLatin1String("neon"))
        return Id::NeonPulse;
    return Id::ClassicAmber;
}

QString UiTheme::menuStyleSheet() const
{
    return QStringLiteral(
               "QMainWindow { background: %1; }"
               "QStatusBar { color: %2; background: %3; border-top: 1px solid %4; }"
               "QMenuBar { background: %5; color: %6; border-bottom: 1px solid %4; }"
               "QMenuBar::item:selected { background: %7; }"
               "QMenu { background: %8; color: %6; border: 1px solid %4; }"
               "QMenu::item:selected { background: %7; }")
        .arg(windowBg.name(), statusFg.name(), statusBg.name(), seam.name(),
             menuBar.name(), menuFg.name(), menuSel.name(), menuBg.name());
}
