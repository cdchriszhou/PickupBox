#include "RadioBrowser.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>
#include <algorithm>

RadioBrowser::RadioBrowser(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
{
}

QVector<RadioRegionDef> RadioBrowser::defaultRegions()
{
    // 国内城市尽量用中文台名检索，并附带省名以拉全量；海外用城市/品牌关键字
    return {
        {QStringLiteral("china"), QStringLiteral("全国热门"),
         {QStringLiteral("中国"), QStringLiteral("CNR"), QStringLiteral("CRI")}, QStringLiteral("CN")},
        {QStringLiteral("beijing"), QStringLiteral("北京"),
         {QStringLiteral("北京"), QStringLiteral("Beijing"), QStringLiteral("BRTV")}, QStringLiteral("CN")},
        {QStringLiteral("shanghai"), QStringLiteral("上海"),
         {QStringLiteral("上海"), QStringLiteral("Shanghai")}, QStringLiteral("CN")},
        {QStringLiteral("guangzhou"), QStringLiteral("广州"),
         {QStringLiteral("广州"), QStringLiteral("Guangzhou"), QStringLiteral("广东")}, QStringLiteral("CN")},
        {QStringLiteral("shenzhen"), QStringLiteral("深圳"),
         {QStringLiteral("深圳"), QStringLiteral("Shenzhen")}, QStringLiteral("CN")},
        {QStringLiteral("chengdu"), QStringLiteral("成都"),
         {QStringLiteral("成都"), QStringLiteral("Chengdu"), QStringLiteral("四川"), QStringLiteral("Sichuan")},
         QStringLiteral("CN")},
        {QStringLiteral("chongqing"), QStringLiteral("重庆"),
         {QStringLiteral("重庆"), QStringLiteral("Chongqing")}, QStringLiteral("CN")},
        {QStringLiteral("hangzhou"), QStringLiteral("杭州"),
         {QStringLiteral("杭州"), QStringLiteral("Hangzhou"), QStringLiteral("浙江")}, QStringLiteral("CN")},
        {QStringLiteral("nanjing"), QStringLiteral("南京"),
         {QStringLiteral("南京"), QStringLiteral("Nanjing"), QStringLiteral("江苏")}, QStringLiteral("CN")},
        {QStringLiteral("wuhan"), QStringLiteral("武汉"),
         {QStringLiteral("武汉"), QStringLiteral("Wuhan"), QStringLiteral("湖北")}, QStringLiteral("CN")},
        {QStringLiteral("xian"), QStringLiteral("西安"),
         {QStringLiteral("西安"), QStringLiteral("陕西")}, QStringLiteral("CN")},
        {QStringLiteral("tianjin"), QStringLiteral("天津"),
         {QStringLiteral("天津"), QStringLiteral("Tianjin")}, QStringLiteral("CN")},
        {QStringLiteral("qingdao"), QStringLiteral("青岛"),
         {QStringLiteral("青岛"), QStringLiteral("Qingdao"), QStringLiteral("山东")}, QStringLiteral("CN")},
        {QStringLiteral("xiamen"), QStringLiteral("厦门"),
         {QStringLiteral("厦门"), QStringLiteral("Xiamen"), QStringLiteral("福建")}, QStringLiteral("CN")},
        {QStringLiteral("kunming"), QStringLiteral("昆明"),
         {QStringLiteral("昆明"), QStringLiteral("云南")}, QStringLiteral("CN")},
        {QStringLiteral("changsha"), QStringLiteral("长沙"),
         {QStringLiteral("长沙"), QStringLiteral("湖南")}, QStringLiteral("CN")},
        {QStringLiteral("zhengzhou"), QStringLiteral("郑州"),
         {QStringLiteral("郑州"), QStringLiteral("河南")}, QStringLiteral("CN")},
        {QStringLiteral("shenyang"), QStringLiteral("沈阳"),
         {QStringLiteral("沈阳"), QStringLiteral("辽宁")}, QStringLiteral("CN")},
        {QStringLiteral("haerbin"), QStringLiteral("哈尔滨"),
         {QStringLiteral("哈尔滨"), QStringLiteral("黑龙江")}, QStringLiteral("CN")},
        {QStringLiteral("fuzhou"), QStringLiteral("福州"),
         {QStringLiteral("福州"), QStringLiteral("福建")}, QStringLiteral("CN")},
        {QStringLiteral("suzhou"), QStringLiteral("苏州"),
         {QStringLiteral("苏州"), QStringLiteral("Suzhou")}, QStringLiteral("CN")},
        {QStringLiteral("dongguan"), QStringLiteral("东莞"),
         {QStringLiteral("东莞"), QStringLiteral("Dongguan")}, QStringLiteral("CN")},
        {QStringLiteral("foshan"), QStringLiteral("佛山"),
         {QStringLiteral("佛山"), QStringLiteral("Foshan")}, QStringLiteral("CN")},
        {QStringLiteral("hongkong"), QStringLiteral("香港"),
         {QStringLiteral("香港"), QStringLiteral("Hong Kong"), QStringLiteral("RTHK")}, QString()},
        {QStringLiteral("taipei"), QStringLiteral("台北"),
         {QStringLiteral("台北"), QStringLiteral("Taipei"), QStringLiteral("台湾")}, QString()},
        {QStringLiteral("sf"), QStringLiteral("旧金山"),
         {QStringLiteral("San Francisco"), QStringLiteral("SomaFM"), QStringLiteral("KEXP")}, QStringLiteral("US")},
        {QStringLiteral("nyc"), QStringLiteral("纽约"),
         {QStringLiteral("New York"), QStringLiteral("WNYC"), QStringLiteral("Jazz")}, QStringLiteral("US")},
        {QStringLiteral("london"), QStringLiteral("伦敦"),
         {QStringLiteral("London"), QStringLiteral("BBC Radio"), QStringLiteral("Classic FM")}, QStringLiteral("GB")},
        {QStringLiteral("amsterdam"), QStringLiteral("阿姆斯特丹"),
         {QStringLiteral("Amsterdam"), QStringLiteral("NPO"), QStringLiteral("Radio")}, QStringLiteral("NL")},
        {QStringLiteral("tokyo"), QStringLiteral("东京"),
         {QStringLiteral("Tokyo"), QStringLiteral("Japan"), QStringLiteral("NHK")}, QStringLiteral("JP")},
        {QStringLiteral("paris"), QStringLiteral("巴黎"),
         {QStringLiteral("Paris"), QStringLiteral("France Inter"), QStringLiteral("FIP")}, QStringLiteral("FR")},
        {QStringLiteral("seoul"), QStringLiteral("首尔"),
         {QStringLiteral("Seoul"), QStringLiteral("Korea"), QStringLiteral("KBS")}, QStringLiteral("KR")},
        {QStringLiteral("singapore"), QStringLiteral("新加坡"),
         {QStringLiteral("Singapore"), QStringLiteral("CNA")}, QString()},
    };
}

QUrl RadioBrowser::pickApiBase()
{
    // radio-browser 官方镜像；失败时由上层重试其它
    static const char *kBases[] = {
        "https://de1.api.radio-browser.info",
        "https://nl1.api.radio-browser.info",
        "https://at1.api.radio-browser.info",
    };
    return QUrl(QString::fromLatin1(kBases[0]));
}

void RadioBrowser::fetchRegion(const RadioRegionDef &region)
{
    if (region.nameQueries.isEmpty()) {
        emit fetchFailed(region.id, tr("该地区未配置检索关键字"));
        return;
    }

    m_activeRegionId = region.id;
    m_accum.clear();
    m_pending = region.nameQueries.size();
    emit fetchStarted(region.name);

    for (const QString &q : region.nameQueries)
        startQuery(region.id, q, region.countryCode);
}

void RadioBrowser::startQuery(const QString &regionId, const QString &nameQuery, const QString &countryCode)
{
    QUrl url = pickApiBase();
    url.setPath(QStringLiteral("/json/stations/search"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("name"), nameQuery);
    query.addQueryItem(QStringLiteral("hidebroken"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("clickcount"));
    query.addQueryItem(QStringLiteral("reverse"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("100"));
    if (!countryCode.isEmpty())
        query.addQueryItem(QStringLiteral("countrycode"), countryCode);
    url.setQuery(query);

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("ShiyinBox/1.0 (Qt6; hi-fi radio)"));
    req.setRawHeader("Accept", "application/json");
    req.setTransferTimeout(20000);

    QNetworkReply *reply = m_nam->get(req);
    reply->setProperty("regionId", regionId);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() { onReplyFinished(reply); });
}

void RadioBrowser::onReplyFinished(QNetworkReply *reply)
{
    reply->deleteLater();
    const QString regionId = reply->property("regionId").toString();
    if (regionId != m_activeRegionId) {
        // 过期请求
        return;
    }

    if (reply->error() != QNetworkReply::NoError) {
        --m_pending;
        if (m_pending <= 0) {
            if (m_accum.isEmpty())
                emit fetchFailed(regionId, tr("加载电台失败：%1").arg(reply->errorString()));
            else
                finishIfDone(regionId);
        }
        return;
    }

    const auto batch = parseStations(reply->readAll());
    for (const RemoteStation &s : batch) {
        bool exists = false;
        for (const RemoteStation &e : m_accum) {
            if ((!s.uuid.isEmpty() && e.uuid == s.uuid) || e.url == s.url || e.name == s.name) {
                exists = true;
                break;
            }
        }
        if (!exists)
            m_accum.append(s);
    }

    --m_pending;
    if (m_pending <= 0)
        finishIfDone(regionId);
}

void RadioBrowser::finishIfDone(const QString &regionId)
{
    if (m_accum.isEmpty()) {
        emit fetchFailed(regionId, tr("该地区暂无可用电台流（可换城市或检查网络）"));
        return;
    }

    std::sort(m_accum.begin(), m_accum.end(),
              [](const RemoteStation &a, const RemoteStation &b) {
                  if (a.clickCount != b.clickCount)
                      return a.clickCount > b.clickCount;
                  // 优先非 HLS，便于兼容
                  if (a.hls != b.hls)
                      return !a.hls && b.hls;
                  return a.name < b.name;
              });

    // 刻度容量：约 0.25 MHz 一档，最多 ~80 台
    constexpr int kMax = 80;
    if (m_accum.size() > kMax)
        m_accum.resize(kMax);

    emit stationsReady(regionId, m_accum);
}

QVector<RemoteStation> RadioBrowser::parseStations(const QByteArray &json)
{
    QVector<RemoteStation> out;
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (!doc.isArray())
        return out;

    const QJsonArray arr = doc.array();
    out.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        if (o.value(QStringLiteral("lastcheckok")).toInt(1) == 0)
            continue;

        RemoteStation s;
        s.uuid = o.value(QStringLiteral("stationuuid")).toString();
        s.name = o.value(QStringLiteral("name")).toString().trimmed();
        const QString resolved = o.value(QStringLiteral("url_resolved")).toString();
        const QString raw = o.value(QStringLiteral("url")).toString();
        s.url = QUrl(resolved.isEmpty() ? raw : resolved);
        s.codec = o.value(QStringLiteral("codec")).toString();
        s.bitrate = o.value(QStringLiteral("bitrate")).toInt();
        s.clickCount = o.value(QStringLiteral("clickcount")).toInt();
        s.hls = o.value(QStringLiteral("hls")).toInt() == 1
                || s.url.path().endsWith(QLatin1String(".m3u8"), Qt::CaseInsensitive);

        if (s.name.isEmpty() || !s.url.isValid() || s.url.scheme().isEmpty())
            continue;
        out.append(s);
    }
    return out;
}
