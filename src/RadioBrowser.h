#pragma once

#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVector>

class QNetworkAccessManager;
class QNetworkReply;

struct RemoteStation {
    QString uuid;
    QString name;
    QUrl url;
    QString codec;
    int bitrate = 0;
    int clickCount = 0;
    bool hls = false;
};

struct RadioRegionDef {
    QString id;
    QString name;           // 面板显示名
    QStringList nameQueries; // radio-browser name= 关键字（合并去重）
    QString countryCode;    // 可选 ISO 国家码
};

class RadioBrowser : public QObject
{
    Q_OBJECT
public:
    explicit RadioBrowser(QObject *parent = nullptr);

    static QVector<RadioRegionDef> defaultRegions();

public slots:
    void fetchRegion(const RadioRegionDef &region);

signals:
    void fetchStarted(const QString &regionName);
    void stationsReady(const QString &regionId, const QVector<RemoteStation> &stations);
    void fetchFailed(const QString &regionId, const QString &message);

private:
    void startQuery(const QString &regionId, const QString &nameQuery, const QString &countryCode);
    void onReplyFinished(QNetworkReply *reply);
    void finishIfDone(const QString &regionId);
    static QVector<RemoteStation> parseStations(const QByteArray &json);
    static QUrl pickApiBase();

    QNetworkAccessManager *m_nam = nullptr;
    QString m_activeRegionId;
    int m_pending = 0;
    QVector<RemoteStation> m_accum;
};
