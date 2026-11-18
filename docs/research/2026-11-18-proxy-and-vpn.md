# Selection of a fixed ISP exit and first-hop VPN

Research date: 18 November 2026. Product statements below come from vendor
documentation. These candidates have not been tested in our Shadowrocket chain.
The current IPRoyal results are in the [incident log](../incidents/2026-11-18-iproyal.md).

## Acceptance criteria

- One dedicated static ISP IPv4. TCP and UDP should use the assigned IP. A
  rotating residential product with a sticky session does not meet the requirement.
- SOCKS5 UDP ASSOCIATE plus real datagram exchange on the ports needed for voice.
  Confirm destination UDP/3478 and /443 and test the native chain on Mac and iPhone.
- One credential set must work concurrently from different and changing public
  source IPs without per-source fees or a narrow source pool. An Amsterdam
  sample produced 12 egress addresses in 20 requests. Unlimited TCP threads
  or a large credential-free allowlist alone does not answer this question.
- Keep the same IP on timely renewal. Ask separately about repair on the same IP
  and whether a fault replacement may assign a new address.
- Use roughly 100 GB per 30 days on one AI exit as the planning target, not a
  measured requirement. Check how upload and download are counted, what happens
  at the threshold, and whether more traffic can be added without changing IP.
- Single-IP test cost, source-network eligibility and support for troubleshooting
  are purchase criteria.

## Shortlist

| Product | Evidence | Traffic per IP | Open questions |
| --- | --- | --- | --- |
| TrueProxies Static ISP | Dedicated per-IP port, same TCP/UDP exit, same IP on timely renewal. $0.99 per day or $2.69/month for one IP. Minimum deposit $3 crypto or $10 card. Password authentication described as working from anywhere. [Product](https://trueproxies.com/proxies/static-isp-proxies/) · [Auth](https://docs.trueproxies.com/proxy-instructions/ip-whitelisting/) · [UDP ports](https://docs.trueproxies.com/proxy-instructions/proxy-protocols/) | No stated GB allowance or per-GB charges. See the product page. | Number and churn of simultaneous source IPs, exact voice ports, same-IP repair. |
| NodeMaven Static ISP | Dedicated IPv4, SOCKS5 TCP/UDP, renew existing IPs. FAQ says simultaneous devices are unlimited. Advertised from $2.99/IP. The smallest preset is three IPs; there is also a custom quantity. [Product](https://nodemaven.com/proxies/dedicated-proxies/) · [Overview](https://docs.nodemaven.com/isp/overview) · [Order form](https://docs.nodemaven.com/quickstart/isp-proxies) · [Devices](https://docs.nodemaven.com/faqs/isp-multiple-devices) · [Renewal](https://docs.nodemaven.com/isp/renew-ip) | Advertises unmetered traffic, billed per IP. See the overview. | Confirm whether custom quantity allows one IP and the checkout total. Confirm distinct public IPs and quick changes on one credential set, voice ports and same-IP repair. |
| ProxyWing ISP NEW | One dedicated static IPv4, $3/month at list price, documented UDP ASSOCIATE. Choose a location on NEW architecture. Terms permit an IP replacement for technical reasons. [Architecture](https://proxywing.com/documentation/proxy-types-overview/isp-proxies) · [Price](https://proxywing.com/prices/isp) · [Terms](https://proxywing.com/policy) | 100 GB per direction per IP per 30 days. Either direction can trigger throttling, concurrency limits, or suspension. Additional capacity is by agreement. See terms §5.3–5.5. | Distinct source IPs, voice ports and same-IP repair. |
| Proxiware Static ISP | Can buy one IP. Dedicated direct endpoint, user/password, SOCKS5 UDP and same IP on funded automatic renewal. [Product FAQ](https://intercom.help/proxiware-llc/en/articles/10672235-static-isp-proxies-countries-protocols-and-setup) · [Auth](https://intercom.help/proxiware-llc/en/articles/10672240-proxiware-setup-resources-and-account-management) | No hard GB limit or per-GB charges. Abnormal usage may be throttled. See product FAQ. | Exact single-IP checkout price, distinct source IPs, voice ports and same-IP repair. |

Proxy-Seller's issued ISP proxy failed UDP ASSOCIATE in our tests. Webshare
and Rayobyte explicitly limit their static plans to TCP. Shifter's current ISP
offer allows the numeric IP to refresh. Byteful and Stat Proxies advertise UDP
on static ISP but list larger entry packages (10 and 25 IPs respectively).
Decodo documents UDP on static ISP, but its FAQ lists service restrictions for
customers originating from Russia and Belarus. Oxylabs has published a similar
restriction. Do not assume eligibility.

- [Prior tests](../network-lab/2026-11-03/README.md)
- [Webshare UDP](https://help.webshare.io/en/articles/8375290-do-you-support-udp-proxy-connections)
- [Rayobyte static UDP](https://portal.rayobyte.com/en/support/solutions/64000161855)
- [Shifter ISP](https://shifter.io/services/isp-proxies)
- [Byteful ISP pricing](https://byteful.com/proxy-service/static-residential-proxies)
- [Stat Proxies ISP terms](https://www.statproxies.com/products/isp)
- [Decodo eligibility and UDP](https://decodo.com/FaQ)
- [Oxylabs policy statement](https://public-files.oxylabs.io/blog/pdf/Oxylabs-Impact-Report-2024.pdf)

## First hop and test order

If preserving the existing IPRoyal IP is the priority, test the full chain
through Xeovo New York in isolation. It showed one egress in eight samples,
but Xeovo states that it does not sell dedicated addresses. Zurich showed two
egresses in 20 samples and failed three of eight IPRoyal 1 MB downloads.
Amsterdam showed 12 egresses in 20 samples. General browsing and the route to
the ISP can use separate entry policies. A managed VPN entry with fixed egress,
or an existing managed server controlled by the user, would make the source
count predictable if the first-hop route itself is reliable. [Xeovo FAQ](https://xeovo.com/faq/).

For a replacement ISP, seek written confirmation first, then use the smallest
order. Use a test profile. Verify TCP exit and real UDP payloads, then test
simultaneous authenticated connections from at least five public sources,
including a newly introduced address. Repeat using the expected egress churn
and compare HTTPS timeouts, 1 MB downloads, and voice on Mac and iPhone.
Keep the live profile outside the test. Confirm retention at renewal and
same-IP fault recovery independently.

Suggested pre-sales question:

> On one dedicated Static ISP IPv4, can the same SOCKS5 username and password
> connect simultaneously from 12 or more distinct public IPv4 source addresses,
> with those source addresses changing between new connections, without
> whitelisting or per-source charges? Please state any active-source cap or
> time window. Does this exact plan relay UDP to destination ports 3478 and
> 443, with the same assigned exit IP as TCP? Does a timely renewal keep that
> IPv4, and can you restore a failed node while retaining it? What traffic
> allowance applies to one IP per 30 days, how are upload and download counted,
> and can I buy more capacity without replacing the exit IPv4?

## Office egress with an assigned public IPv4

For an authorized Seattle office Mac mini with inbound reachability and the
expected static IPv4 as its outbound NAT, prefer one direct encrypted
Shadowsocks node in Shadowrocket. Use shadowsocks-rust (ssserver) on the
Mac mini, one approved TCP/UDP port, and a strong private key. Start with
the AEAD cipher already supported in our tooling, chacha20-ietf-poly1305,
and test native UDP independently. Restrict outbound access to public
destinations and keep the proxy isolated from office services. The
OPENAI and CLAUDE groups can select this node with REJECT on failure.
OTHER can continue using its existing policy. No IPRoyal slot is used
on that office-exit path.
[Server options and ACL](https://github.com/shadowsocks/shadowsocks-rust).

A public IPv4 only establishes the office address. Confirm which IP the
Mac mini actually uses for egress and whether the perimeter can make a
single approved TCP/UDP port reachable. If the office already operates
a suitable WireGuard gateway, test its office egress as an alternative
before adding an office-hosted service. Plain SOCKS5 is suitable inside
a private encrypted tunnel; the standard username/password method
sends the password in cleartext. [SOCKS5 authentication](https://datatracker.ietf.org/doc/html/rfc1929).
The current profile builder assumes SOCKS5 for ISP exits, so pilot
with a separate Shadowrocket profile first. Update builder validation
and the expected guard IP only when migrating to the office address.
