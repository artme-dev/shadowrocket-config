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
subscription. For a new provider prioritize Red Shield's exportable VLESS
and a low-commitment RuSolv import test. Keep Amnezia as a candidate subject
to the export and local-reachability checks above. A native-app-only service
can serve as an emergency backup but cannot directly replace this first hop.

Private raw evidence in `out/diagnostics/2026-11-18/`:
`xeovo-only-185403.private.json`, `xeovo-protocols-185453.private.json`,
and `xeovo-current-source.private.json`. Never commit the source snapshot.
