using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using C64GameServer.Protocol;

namespace C64GameServer;

/// <summary>
/// The web dashboard: plain HTTP (no TLS) on the dashboard port, one page, live via Server-Sent Events.
/// A minimal HTTP server on a TcpListener, so no administrator rights are needed to listen on the LAN
/// (HttpListener would need a URL reservation for that on Windows).
/// </summary>
internal sealed class Dashboard(ServerHost host, int port)
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public async Task Run(CancellationToken ct)
    {
        TcpListener listener;
        try
        {
            listener = new TcpListener(IPAddress.Any, port);
            listener.Start();
        }
        catch (SocketException e)
        {
            Console.WriteLine($"Dashboard not started (port {port}): {e.Message}");
            return;
        }
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(ct);
                _ = Task.Run(() => Handle(client, ct), ct);
            }
        }
        catch (OperationCanceledException) { }
        finally { listener.Stop(); }
    }

    private async Task Handle(TcpClient client, CancellationToken ct)
    {
        using (client)
        {
            try
            {
                var stream = client.GetStream();
                var reader = new StreamReader(stream, Encoding.ASCII);
                var requestLine = await reader.ReadLineAsync(ct) ?? "";
                while (!string.IsNullOrEmpty(await reader.ReadLineAsync(ct))) { } // headers
                var parts = requestLine.Split(' ');
                if (parts.Length < 2) return;
                var (method, path) = (parts[0], parts[1].Split('?')[0]); // the query (e.g. ?static) is for the page script

                if (path == "/events")
                {
                    await Write(stream, "200 OK", "text/event-stream", null, extraHeaders: "Cache-Control: no-cache\r\n");
                    while (!ct.IsCancellationRequested && client.Connected)
                    {
                        var data = Encoding.UTF8.GetBytes("data: " + StatusJson() + "\n\n");
                        await stream.WriteAsync(data, ct);
                        await Task.Delay(1000, ct);
                    }
                    return;
                }
                if (path == "/api/status")
                {
                    await Write(stream, "200 OK", "application/json", StatusJson());
                    return;
                }
                if (method == "POST" && path.StartsWith("/api/kick/") && byte.TryParse(path[10..], out var cid))
                {
                    bool ok;
                    lock (host.Lock) ok = host.Core.Kick(cid, DateTime.UtcNow);
                    await Write(stream, ok ? "200 OK" : "404 Not Found", "text/plain", ok ? "ok" : "unknown");
                    return;
                }
                if (method == "POST" && path.StartsWith("/api/end/") && byte.TryParse(path[9..], out var sid))
                {
                    bool ok;
                    lock (host.Lock) ok = host.Core.AdminEndSession(sid, DateTime.UtcNow);
                    await Write(stream, ok ? "200 OK" : "404 Not Found", "text/plain", ok ? "ok" : "unknown");
                    return;
                }
                if (path is "/" or "/index.html")
                {
                    await Write(stream, "200 OK", "text/html; charset=utf-8", Page);
                    return;
                }
                await Write(stream, "404 Not Found", "text/plain", "not found");
            }
            catch (Exception e) when (e is IOException or SocketException or OperationCanceledException) { }
        }
    }

    private static async Task Write(NetworkStream s, string status, string type, string? body, string extraHeaders = "")
    {
        var bytes = body == null ? null : Encoding.UTF8.GetBytes(body);
        var header = $"HTTP/1.1 {status}\r\nContent-Type: {type}\r\n{extraHeaders}" +
                     (bytes != null ? $"Content-Length: {bytes.Length}\r\nConnection: close\r\n" : "") + "\r\n";
        await s.WriteAsync(Encoding.ASCII.GetBytes(header));
        if (bytes != null) await s.WriteAsync(bytes);
    }

    private string StatusJson()
    {
        var now = DateTime.UtcNow;
        lock (host.Lock)
        {
            var core = host.Core;
            var status = new
            {
                addresses = Program.LocalAddresses().Select(a => a.ToString()).ToList(),
                port = _gamePort,
                uptime = (now - core.StartedAt).ToString(@"d\.hh\:mm\:ss"),
                games = core.Games.All.Select(g => new { id = g.GameId, name = g.Name }).ToList(),
                players = core.Clients.OrderBy(c => c.Id).Select(c => new
                {
                    id = c.Id,
                    nick = c.Nick,
                    kind = c.IsBot ? "bot" : "human",
                    address = c.EndPoint.ToString(),
                    game = core.Games.Get(c.GameId)?.Name ?? c.GameId.ToString(),
                    state = c.State switch
                    {
                        Core.ClientState.Lobby => "lobby",
                        Core.ClientState.Challenged => "challenged",
                        _ => $"in game (session {c.Session?.Id})",
                    },
                    ping = c.PingMs is { } p ? $"{p:0} ms" : "-",
                    seen = $"{(now - c.LastSeen).TotalSeconds:0.0} s ago",
                }).ToList(),
                sessions = core.Sessions.Select(s => new
                {
                    id = s.Id,
                    game = core.Games.Get(s.GameId)?.Name,
                    players = string.Join(" vs ", s.Players.Select(p => p.Nick)),
                    duration = (now - s.Started).ToString(@"mm\:ss"),
                    started = s.StartAcked.Count == s.Players.Count ? "yes" : $"{s.StartAcked.Count}/{s.Players.Count}",
                    traffic = $"{s.MessagesRelayed} msgs, {s.BytesRelayed} bytes",
                    rate = $"{s.MessagesRelayed / Math.Max(1, (now - s.Started).TotalSeconds):0.0} msgs/s",
                    status = core.Games.Get(s.GameId)?.Status(s).Select(f => new { name = f.Name, value = f.Value }).ToList(),
                    recent = s.Recent.Reverse().Take(12)
                        .Select(r => $"{r.Time:HH:mm:ss.fff} {r.From,-8} {Messages.Hex(r.Data)}").ToList(),
                }).ToList(),
                challenges = core.Challenges.Select(c => new
                {
                    id = c.Id,
                    players = string.Join(" vs ", c.Players.Select(p => p.Nick + (c.Accepted.Contains(p) ? " (accepted)" : ""))),
                    age = $"{(now - c.Created).TotalSeconds:0} s",
                }).ToList(),
                stats = new { invalid = core.InvalidDatagrams, unknown = core.UnknownDatagrams, sent = host.Transport.Sent },
                log = core.Log.Snapshot(300).Select(e => new
                {
                    time = e.Time.ToLocalTime().ToString("HH:mm:ss"),
                    category = e.Category,
                    text = e.Text,
                    player = e.Player,
                    session = e.Session,
                }).ToList(),
            };
            return JsonSerializer.Serialize(status, Json);
        }
    }

    private static int _gamePort = 6465;

    /// <summary>The game port shown on the page (from server.json).</summary>
    public static void SetGamePort(int p) => _gamePort = p;

    private const string Page = """
<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>C64 Game Server</title>
<style>
 :root { --bg:#1d1b4a; --panel:#2b2a6b; --text:#d8d6ff; --dim:#9a97d8; --accent:#7b78ff; --ok:#7fe0a0; --bad:#ff8080; }
 body { background:var(--bg); color:var(--text); font:14px/1.4 system-ui, sans-serif; margin:0; padding:16px; }
 h1 { margin:0 0 4px; font-size:20px } h2 { font-size:15px; margin:0 0 8px; color:var(--dim); text-transform:uppercase; letter-spacing:.05em }
 .connect { font:bold 28px ui-monospace, monospace; color:#fff; } .grid { display:grid; gap:16px; grid-template-columns:repeat(auto-fit,minmax(420px,1fr)); }
 .panel { background:var(--panel); border-radius:8px; padding:12px; overflow:auto }
 table { border-collapse:collapse; width:100% } td, th { text-align:left; padding:3px 8px 3px 0; vertical-align:top } th { color:var(--dim); font-weight:normal }
 button { background:var(--accent); color:#fff; border:0; border-radius:4px; padding:2px 8px; cursor:pointer }
 pre { margin:4px 0 0; font:12px ui-monospace, monospace; color:var(--dim); white-space:pre-wrap }
 .warn { color:var(--bad) } .desync { color:var(--bad) } .connect-small { color:var(--dim) }
 input { background:var(--bg); color:var(--text); border:1px solid var(--accent); border-radius:4px; padding:2px 6px }
</style></head><body>
<h1>C64 Game Server</h1>
<div class="connect-small">LAN only, no encryption. C64s connect to:</div>
<div class="connect" id="connect">...</div>
<p class="connect-small" id="summary"></p>
<div class="grid">
 <div class="panel"><h2>Players</h2><table id="players"></table></div>
 <div class="panel"><h2>Sessions</h2><div id="sessions"></div><h2 style="margin-top:12px">Challenges</h2><table id="challenges"></table></div>
 <div class="panel" style="grid-column:1/-1"><h2>Events</h2>
  filter: <input id="filter" placeholder="player, session or text"> <table id="log"></table></div>
</div>
<script>
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
async function post(url) { await fetch(url, {method:'POST'}); }
let last = null;
function render(s) {
  last = s;
  document.getElementById('connect').textContent = s.addresses.map(a => a + ' : ' + s.port).join('   ');
  document.getElementById('summary').textContent =
    `uptime ${s.uptime} · ${s.players.length} players · ${s.sessions.length} sessions · games: ${s.games.map(g => g.id + ' ' + g.name).join(', ')} · invalid packets: ${s.stats.invalid}`;
  document.getElementById('players').innerHTML = '<tr><th>name</th><th>kind</th><th>address</th><th>game</th><th>status</th><th>ping</th><th>last seen</th><th></th></tr>' +
    s.players.map(p => `<tr><td>${esc(p.nick)}</td><td>${p.kind === 'bot' ? 'bot' : 'human'}</td><td>${esc(p.address)}</td><td>${esc(p.game)}</td><td>${esc(p.state)}</td><td>${esc(p.ping)}</td><td>${esc(p.seen)}</td>
      <td><button onclick="post('/api/kick/${p.id}')">kick</button></td></tr>`).join('');
  document.getElementById('sessions').innerHTML = s.sessions.length ? s.sessions.map(x => `
    <div style="margin-bottom:10px"><b>#${x.id} ${esc(x.game)}</b>: ${esc(x.players)} · ${x.duration} · started: ${x.started} · ${esc(x.traffic)} · ${esc(x.rate)}
    <button onclick="post('/api/end/${x.id}')">end</button>
    <table>${(x.status || []).map(f => `<tr><th>${esc(f.name)}</th><td>${esc(f.value)}</td></tr>`).join('')}</table>
    <pre>${x.recent.map(esc).join('\n')}</pre></div>`).join('') : '<span class="connect-small">none</span>';
  document.getElementById('challenges').innerHTML = s.challenges.map(c => `<tr><td>#${c.id}</td><td>${esc(c.players)}</td><td>${c.age}</td></tr>`).join('');
  renderLog();
}
function renderLog() {
  if (!last) return;
  const f = document.getElementById('filter').value.toLowerCase();
  document.getElementById('log').innerHTML = last.log
    .filter(e => !f || [e.text, e.player, e.session, e.category].join(' ').toLowerCase().includes(f))
    .map(e => `<tr class="${e.category === 'desync' || e.category === 'error' ? 'warn' : ''}"><td>${e.time}</td><td>${esc(e.category)}</td><td>${esc(e.text)}</td></tr>`).join('');
}
document.getElementById('filter').oninput = renderLog;
fetch('/api/status').then(r => r.json()).then(render); // show the state at once, then live updates
if (!location.search.includes('static')) { // /?static: one snapshot, no live connection (e.g. for screenshots)
  const ev = new EventSource('/events');
  ev.onmessage = m => render(JSON.parse(m.data));
}
</script></body></html>
""";
}
