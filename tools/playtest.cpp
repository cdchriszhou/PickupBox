// Minimal QMediaPlayer smoke test — build & run from qt6/
#include <QCoreApplication>
#include <QAudioOutput>
#include <QMediaPlayer>
#include <QTimer>
#include <QUrl>
#include <QFileInfo>
#include <cstdio>

int main(int argc, char *argv[])
{
    qputenv("QT_MEDIA_BACKEND", "ffmpeg");
    qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", ",");
    qputenv("QT_LOGGING_RULES", "qt.multimedia.*=true");

    QCoreApplication app(argc, argv);
    const QString path = argc > 1
        ? QString::fromLocal8Bit(argv[1])
        : QStringLiteral("D:/Works/CursorSpace/KaLaOK/assets/demo_tone.mp3");

    std::printf("file: %s exists=%d size=%lld\n",
                qPrintable(path),
                QFileInfo::exists(path),
                (long long)QFileInfo(path).size());

    QMediaPlayer player;
    QAudioOutput out;
    out.setVolume(0.8f);
    player.setAudioOutput(&out);

    QObject::connect(&player, &QMediaPlayer::errorOccurred, &app, [&](QMediaPlayer::Error, const QString &e) {
        std::printf("ERROR: %s\n", qPrintable(e));
        app.exit(2);
    });
    QObject::connect(&player, &QMediaPlayer::mediaStatusChanged, &app, [&](QMediaPlayer::MediaStatus s) {
        std::printf("status=%d duration=%lld\n", int(s), (long long)player.duration());
        if (s == QMediaPlayer::LoadedMedia || s == QMediaPlayer::BufferedMedia)
            player.play();
    });
    QObject::connect(&player, &QMediaPlayer::playbackStateChanged, &app, [&](QMediaPlayer::PlaybackState st) {
        std::printf("playbackState=%d pos=%lld\n", int(st), (long long)player.position());
    });
    QObject::connect(&player, &QMediaPlayer::positionChanged, &app, [&](qint64 pos) {
        if (pos > 500) {
            std::printf("OK playing pos=%lld\n", (long long)pos);
            app.exit(0);
        }
    });

    player.setSource(QUrl::fromLocalFile(path));
    player.play();

    QTimer::singleShot(8000, &app, [&]() {
        std::printf("TIMEOUT status=%d state=%d pos=%lld dur=%lld err=%s\n",
                    int(player.mediaStatus()),
                    int(player.playbackState()),
                    (long long)player.position(),
                    (long long)player.duration(),
                    qPrintable(player.errorString()));
        app.exit(1);
    });

    return app.exec();
}
