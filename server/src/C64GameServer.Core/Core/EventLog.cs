namespace C64GameServer.Core;

public sealed record LogEntry(DateTime Time, string Category, string Text, string? Player, byte? Session);

/// <summary>In-memory event log (for the dashboard) plus an optional log file.</summary>
public sealed class EventLog
{
    private readonly object _lock = new();
    private readonly LinkedList<LogEntry> _entries = new();
    private readonly int _capacity;
    private readonly string? _file;
    private readonly bool _console;

    public EventLog(string? file = null, int capacity = 2000, bool console = false)
    {
        _file = file;
        _capacity = capacity;
        _console = console;
    }

    public void Add(DateTime time, string category, string text, string? player = null, byte? session = null)
    {
        var e = new LogEntry(time, category, text, player, session);
        lock (_lock)
        {
            _entries.AddLast(e);
            while (_entries.Count > _capacity) _entries.RemoveFirst();
        }
        var line = $"{time:yyyy-MM-dd HH:mm:ss.fff} [{category}] {text}";
        if (_console) Console.WriteLine(line);
        if (_file != null)
        {
            try { File.AppendAllText(_file, line + Environment.NewLine); }
            catch (IOException) { /* the log must never stop the server */ }
        }
    }

    public IReadOnlyList<LogEntry> Snapshot(int max = 500)
    {
        lock (_lock) return _entries.Reverse().Take(max).ToList();
    }
}
