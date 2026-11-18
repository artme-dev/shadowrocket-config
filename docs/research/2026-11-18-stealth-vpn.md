# Stealth VPN shortlist for the current access network

This research covers the first hop. The office exit and commercial fixed ISP
comparison are in [ISP and office research](2026-11-18-proxy-and-vpn.md).

## What to select for

The mandatory combination is an interface we can use in Shadowrocket on
Mac and iPhone, a stealth transport that actually connects from the user's
Russian access networks, and service that stays usable across reconnects.
Prefer an importable standard node or subscription and at least two
independent reachable endpoints. A vendor's native-app stealth mode does
not establish the same capability for an exported node.

Test on the current Mac network and separately on iPhone Wi-Fi and mobile
data. Compare repeated fresh TCP connections, latency, downloads and
timeouts. For the AI chain add native UDP payload/voice tests and repeat
the egress-IP check. IPRoyal's source cap is a separate compatibility
requirement. For general traffic multiple output IPs can be acceptable.

## Earlier work

- [November 3 screening](../network-lab/2026-11-03/entry-pool.md) sampled 34
  Blanc and Xeovo configurations from one Mac network. Only 3 of 18 Xeovo
  WS alternatives passed; 3 of 4 Hysteria2 alternatives passed.
- [November 4 native acceptance](../network-lab/2026-11-04/README.md) verified
  the selected TCP/UDP chain in Shadowrocket. Hysteria2 was excluded from
  the shared ISP path after native UDP failures in tested combinations.
- [November 18 incident](../incidents/2026-11-18-iproyal.md) showed
  that the old Xeovo New York VLESS/WS node still worked. Four other saved
  Xeovo entries were unavailable in the isolated tests. Blanc Amsterdam's
  rapidly changing egress made it a poor match for the IPRoyal source cap.

## Current managed candidates

| Provider | Why it is on the list | What remains |
| --- | --- | --- |
| BlancVPN | Existing VLESS/Reality capability and observed connectivity from the Mac. | Verify representative nodes on mobile; distinguish endpoint diversity from city labels. Keep Amsterdam away from source-capped ISP tests. |
| Xeovo Stealth | Official Shadowrocket subscription and a working saved New York endpoint in this network. [Import instructions](https://hub.xeovo.com/posts/25-stealth-proxy-overhaul-subscriptions-new-guides) · [Status](https://status.xeovo.com/) | Preserve the working saved endpoint while screening current subscription nodes. A provider-wide status does not measure the user's path. |
| Red Shield VPN | Vendor documents separately exportable VLESS (XTLS-Reality). [VLESS announcement](https://redshieldvpn.com/ru/news) · [Manual configuration](https://redshieldvpn.com/ru/faq) | Confirm Shadowrocket import on both platforms and test the actual manual node. Do not infer its reliability from RedLink in the native app. |
| RuSolv | Vendor publishes VLESS+Reality subscriptions and offers limited free traffic for a pilot. [Setup](https://rusolv.com/docs) · [Plans](https://rusolv.com/) | Documented clients include Happ/Hiddify; Shadowrocket import and local connectivity still need testing. |
| Amnezia Premium | Vendor offers VLESS Reality and documentation on alternative clients. [Premium](https://amnezia.org/ru/premium) · [Alternative clients](https://docs.amnezia.org/documentation/alternative-clients/) | Confirm specific Premium configuration export/import and working locations from the user's networks. |

November 18 fresh Xeovo subscription: 548 records across several protocols.
Its names now use `xeo`; historical exports used `xeovo`. The builder
recognizes both. Old Netherlands SS and New York identifiers are absent from
the current catalog. Germany Trojan, Sweden and Singapore are present.
A fresh build with the old profile settings still needs explicit decisions
for the two absent identifiers; an offline historical snapshot remains
reproducible. Do not silently replace the functioning legacy New York node.

The live checks around 18:54–18:55 Novosibirsk time used temporary sing-box
listeners bound to the Mac physical network. No IPRoyal connections were made.
The first batch (12 current configurations, predominantly VLESS WS/TLS) had
0/24 successes. A second batch (9 current configurations with Shadowsocks,
Trojan TLS and Hysteria2 across New York, Netherlands and Germany) had
0/18 successes. Existing snapshot controls succeeded: old Xeovo New York 3/3
with one public egress in this run, and Blanc Zurich 3/3. The fresh candidate
failures are from this access network and test client. They do not establish
a provider-wide outage or imply that every one of the 548 records fails.

The saved New York node is useful as a backup, pending tests on iPhone Wi-Fi
and mobile data. Do not replace it solely because it is absent from a new
subscription. For new providers, use the expanded shortlist below. A native-app-only
service can serve as an emergency backup and requires a separate client.

Private raw evidence in `out/diagnostics/2026-11-18/`:
`xeovo-only-185403.private.json`, `xeovo-protocols-185453.private.json`,
and `xeovo-current-source.private.json`. Never commit the source snapshot.

## Expanded managed VPN shortlist

Follow-up research checked the exact subscription or export available for
third-party clients. The ordering below supersedes the earlier candidate order.
These are pilot candidates, with no local tunnel results yet.

| Pilot order | Service | Shadowrocket and protocol evidence | Trial and caveats |
| --- | --- | --- | --- |
| 1 | Tainet | Vendor instructions explicitly cover importing its own subscription into Shadowrocket on iOS. Vendor lists VLESS Reality, Shadowsocks 2022 and Hysteria2. [Import](https://tainet.top/blog/shadowrocket-setup-guide/) · [Protocols](https://tainet.top/) | Seven days free without card per import guide. Verify the exact Apple Silicon Mac import and which nodes the subscription sends to Shadowrocket. Basic plan lists five device slots and a separate 10 GB mobile fallback allowance. [Pricing](https://tainet.top/pricing/) |
| 2 | Mavrodiy VPN | Vendor has a Shadowrocket guide for iPhone/iPad and Apple Silicon Mac, and documents that it serves a node list to Shadowrocket. Advertises Reality, XHTTP, and Hysteria2. [Import](https://mavrodiyvpn.com/apps/shadowrocket) · [Feed format](https://mavrodiyvpn.com/blog/subscription-key-config) · [Transports](https://mavrodiyvpn.com/vless) | Three days for RUB 10 on one device, crypto via TON. Monthly RUB 249 for three devices; standard plan slows to 10 Mbps past 300 GB per 30 days. Operator status is vendor measurements, not our test. [Trial](https://mavrodiyvpn.com/trial) · [Pricing](https://mavrodiyvpn.com/pricing) · [Status](https://mavrodiyvpn.com/status) |
| 3 | RuSolv | VLESS Reality subscription for external clients, raw VLESS export is documented. Shadowrocket-specific import is not documented for this plan. [FAQ](https://rusolv.com/docs/faq) | Free VLESS: 10 GB/month, one device and free-tier locations. Start RUB 199/month for two devices. Confirm raw node or ordinary feed imports. [Plans](https://rusolv.com/) |
| 4 | WBVLESS | Vendor publishes a Shadowrocket subscription guide but asks buyers to verify the exact feed in their client version. [Guide](https://wbvless.com/apps/shadowrocket/) | Free day with 10 GB, then RUB 50/week or RUB 189/month, three devices on the paid standard plan. Verify the transport actually offered in the trial feed. |
| 5 | Liberty VPN | Vendor documents its own subscription import in Shadowrocket on iPhone/iPad. [Import](https://proxyliberty.com/instructions/apple-tv/) | Personal list price USD 6.99/month. Trial terms vary by account. Confirm Mac import and the transport used by its feed. [Plans](https://proxyliberty.com/us/) |
| Conditional | Red Shield | Exportable manual VLESS/XTLS-Reality; native app's RedLink is a separate path. [Manual VLESS](https://redshieldvpn.com/ru/help/vpn_on_linux/vless_ubuntu_debian_gui) | Vendor recommends its app over manual configs in countries with VPN filtering. Buy only after confirming the exact manual path suits the intended client. [Support FAQ](https://redshieldvpn.com/en/help/faq/service) |
| Separate app backup | Amnezia Premium | Vendor offers VLESS Reality in its app. Its Premium dashboard documents downloadable AmneziaWG configs and a supported-client list. The generic alternative-client guide for XRay starts with a self-hosted server. [Premium dashboard](https://docs.amnezia.org/documentation/instructions/personal_dashboard/#configuration-files) · [Alternative clients](https://docs.amnezia.org/documentation/alternative-clients/) | No supported Premium Reality export into Shadowrocket confirmed. Do not count it as a drop-in fixture for this profile. |

Independent context: [OONI Russia report](https://ooni.org/post/2024-russia-report/)
documents that filtering varies by network and protocol, but its website
measurements cannot establish VPN tunnel performance. [Freedom Checker](https://freedomchecker.ateo.digital/en/)
describes regional physical probes, including Novosibirsk. Use those as leads
only, because their probe access network and credentials may differ from ours.

Pilot two different providers in separate profiles. Confirm import of at least
two endpoints per provider, check Wi-Fi and cellular independently, and repeat
after reconnecting. Record TCP/HTTPS success and timeouts first. If the new
entry will serve the fixed ISP chain, check public source-IP count, then
repeat through the fixed exit and verify UDP payloads and native voice.
