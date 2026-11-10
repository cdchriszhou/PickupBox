#include "MainWindow.h"

#include <QApplication>
#include <QByteArray>
#include <QColor>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QIcon>
#include <QPalette>

static QIcon loadAppIcon()
{
    // Prefer multi-size ICO for crisp taskbar / title-bar rendering
    QIcon ico(QStringLiteral(":/fh-kaok.ico"));
    if (!ico.isNull())
        return ico;
    return QIcon(QStringLiteral(":/fh-kaok-icon.png"));
}

int main(int argc, char *argv[])
{
    // 必须用 FFmpeg：网络电台（HTTP/AAC/MP3 流）Windows 后端基本不可用；
    // 本地 MP3 同样由 FFmpeg 解码。可用环境变量 QT_MEDIA_BACKEND 覆盖。
    if (qgetenv("QT_MEDIA_BACKEND").isEmpty())
        qputenv("QT_MEDIA_BACKEND", QByteArrayLiteral("ffmpeg"));
    if (qgetenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES").isEmpty())
        qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", QByteArrayLiteral(","));

    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("拾音盒子"));
    QApplication::setApplicationDisplayName(QStringLiteral("拾音盒子"));
    QApplication::setOrganizationName(QStringLiteral("KaLaOK"));
    // 确保能找到同目录下的 multimedia / platforms 插件（含 ffmpegmediaplugin）
    const QString appDir = QCoreApplication::applicationDirPath();
    QCoreApplication::addLibraryPath(appDir);
    QCoreApplication::addLibraryPath(appDir + QStringLiteral("/plugins"));
    const QIcon appIcon = loadAppIcon();
    app.setWindowIcon(appIcon);

    QPalette palette;
    palette.setColor(QPalette::Window, QColor(26, 26, 28));
    palette.setColor(QPalette::WindowText, QColor(230, 230, 230));
    palette.setColor(QPalette::Base, QColor(20, 20, 22));
    palette.setColor(QPalette::Text, QColor(230, 230, 230));
    app.setPalette(palette);

    MainWindow win;
    win.setWindowIcon(appIcon);
    win.show();

    // 用 QApplication::arguments() 保留中文路径，勿用 fromLocal8Bit(argv)
    const QStringList args = QApplication::arguments();
    if (args.size() > 1) {
        const QString arg = args.at(1);
        if (QFileInfo(arg).isDir()) {
            QDir dir(arg);
            QStringList files;
            const QStringList names = dir.entryList(
                QStringList{QStringLiteral("*.mp3"), QStringLiteral("*.wav"),
                            QStringLiteral("*.flac"), QStringLiteral("*.ogg"),
                            QStringLiteral("*.m4a"), QStringLiteral("*.aac"),
                            QStringLiteral("*.wma")},
                QDir::Files, QDir::Name);
            for (const QString &n : names)
                files.append(dir.absoluteFilePath(n));
            if (!files.isEmpty())
                win.loadPlaylist(files);
        } else {
            win.loadFile(arg);
        }
    }

    return app.exec();
}
