// Exercise AudioEngine playFile -> playFile (track switch) like the app.
#include "../src/AudioEngine.h"
#include "../src/PaintKit.h"
#include "../src/PaintKit.cpp"
#include "../src/AudioEngine.cpp"

#include <QCoreApplication>
#include <QTimer>
#include <cstdio>

int main(int argc, char *argv[])
{
    qputenv("QT_MEDIA_BACKEND", "ffmpeg");
    qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", ",");

    QCoreApplication app(argc, argv);
    const QString a = argc > 1 ? QString::fromLocal8Bit(argv[1])
                               : QStringLiteral("D:/Works/CursorSpace/KaLaOK/assets/demo_tone.mp3");
    const QString b = argc > 2 ? QString::fromLocal8Bit(argv[2]) : a;

    AudioEngine eng;
    int phase = 0;

    QObject::connect(&eng, &AudioEngine::errorOccurred, &app, [](const QString &e) {
        std::printf("ENGINE ERROR: %s\n", qPrintable(e));
    });
    QObject::connect(&eng, &AudioEngine::playingChanged, &app, [&](bool on) {
        std::printf("playing=%d phase=%d path=%s\n", int(on), phase, qPrintable(eng.currentPath()));
        if (on && phase == 0) {
            QTimer::singleShot(400, &app, [&]() {
                phase = 1;
                std::printf("SWITCH -> %s\n", qPrintable(b));
                eng.playFile(b);
                phase = 2;
            });
        } else if (on && phase == 2) {
            std::printf("SECOND PLAYING OK\n");
            QTimer::singleShot(300, &app, [&]() { app.exit(0); });
        }
    });

    eng.playFile(a);
    QTimer::singleShot(15000, &app, [&]() {
        std::printf("TIMEOUT phase=%d playing=%d\n", phase, int(eng.isPlaying()));
        app.exit(1);
    });
    return app.exec();
}
