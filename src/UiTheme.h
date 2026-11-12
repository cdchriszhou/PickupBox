#pragma once

#include <QColor>
#include <QString>
#include <QVector>

struct UiTheme {
    enum class Id {
        ClassicAmber = 0, // 经典琥珀
        SilverStudio = 1, // 银灰工作室
        WalnutLounge = 2, // 胡桃客厅
        NeonPulse = 3     // 霓虹脉冲
    };

    Id id = Id::ClassicAmber;
    QString key;
    QString nameZh;

    QColor windowBg;
    QColor statusBg;
    QColor statusFg;

    QColor rackTop;
    QColor rackMid;
    QColor rackBot;
    QColor rackEdge;

    QColor chassisLo;
    QColor chassisMid;
    QColor chassisHi;
    QColor baffle;
    QColor baffleDeep;
    QColor plateGold;
    QColor screw;

    QColor ampFace;
    QColor ampWell;
    QColor metal;
    QColor seam;

    QColor accent;
    QColor accentHot;
    QColor accentDim;
    QColor ledWarm;
    QColor ledCool;
    QColor ledDanger;

    QColor label;
    QColor labelDim;
    QColor labelHot;
    QColor vfdGlow;
    QColor vizCore;
    QColor vizGlow;

    QColor menuBg;
    QColor menuFg;
    QColor menuSel;
    QColor menuBar;

    QString menuStyleSheet() const;
    static UiTheme make(Id id);
    static QVector<UiTheme> all();
    static Id idFromKey(const QString &key);
};
