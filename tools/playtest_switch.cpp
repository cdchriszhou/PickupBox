// Simulate first track play then switch to second track (rebuild player).
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

    QCoreApplication app(argc, argv);
    const QString a = argc > 1 ? QString::fromLocal8Bit(argv[1])
                               : QStringLiteral("D:/Works/CursorSpace/KaLaOK/assets/demo_tone.mp3");
    const QString b = argc > 2 ? QString::fromLocal8Bit(argv[2]) : a;
    std::printf("track1: %s\ntrack2: %s\n", qPrintable(a), qPrintable(b));

    QAudioOutput out;
    out.setVolume(0.8f);

    auto *p1 = new QMediaPlayer(&app);
    p1->setAudioOutput(&out);

    QObject::connect(p1, &QMediaPlayer::errorOccurred, &app, [](QMediaPlayer::Error, const QString &e) {
        std::printf("ERROR1: %s\n", qPrintable(e));
    });
    QObject::connect(p1, &QMediaPlayer::mediaStatusChanged, &app, [p1](QMediaPlayer::MediaStatus s) {
        std::printf("status1=%d\n", int(s));
        if (s == QMediaPlayer::LoadedMedia || s == QMediaPlayer::BufferedMedia)
            p1->play();
        if (s == QMediaPlayer::EndOfMedia)
            std::printf("EndOfMedia on track1 pos=%lld\n", (long long)p1->position());
    });

    QObject::connect(p1, &QMediaPlayer::positionChanged, &app, [&](qint64 pos) {
        if (pos <= 300)
            return;
        std::printf("FIRST OK pos=%lld — rebuild switch\n", (long long)pos);
        QObject::disconnect(p1, nullptr, &app, nullptr);
        p1->stop();
        p1->setAudioOutput(nullptr);
        p1->deleteLater();

        auto *p2 = new QMediaPlayer(&app);
        p2->setAudioOutput(&out);
        QObject::connect(p2, &QMediaPlayer::errorOccurred, &app, [](QMediaPlayer::Error, const QString &e) {
            std::printf("ERROR2: %s\n", qPrintable(e));
            QCoreApplication::exit(2);
        });
        QObject::connect(p2, &QMediaPlayer::mediaStatusChanged, &app, [p2](QMediaPlayer::MediaStatus s) {
            std::printf("status2=%d\n", int(s));
            if (s == QMediaPlayer::LoadedMedia || s == QMediaPlayer::BufferedMedia)
                p2->play();
        });
        QObject::connect(p2, &QMediaPlayer::positionChanged, &app, [p2](qint64 pos2) {
            if (pos2 > 300) {
                std::printf("SECOND OK pos=%lld\n", (long long)pos2);
                QCoreApplication::exit(0);
            }
        });
        p2->setSource(QUrl::fromLocalFile(b));
        p2->play();
    });

    p1->setSource(QUrl::fromLocalFile(a));
    p1->play();

    QTimer::singleShot(12000, &app, []() {
        std::printf("TIMEOUT\n");
        QCoreApplication::exit(1);
    });
    return app.exec();
}
