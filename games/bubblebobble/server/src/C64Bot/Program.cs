using C64GameServer.Bots;

namespace C64Bot;

/// <summary>Command line front end of the bot (C64GameServer.Bots.BotClient).</summary>
internal static class Program
{
    private static int Main(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h"))
        {
            Console.WriteLine("""
C64Bot - test client for the C64 Game Server (behaves like a C64 playing Wizard of Wor)

  --server HOST[:PORT]   server (default 127.0.0.1:6465)
  --nick NAME            nickname, A-Z 0-9, max 8 (default BOT)
  --game ID              game id (default 1 = Wizard of Wor)
  --games N              sessions to play, 0 = forever (default 1)
  --ticks N              ticks per session, then game over (default 3600 = 60 s)
  --read-delay MS        handle received packets only every MS ms (the C64 Ultimate read waits up to 40 ms)
  --loss PERCENT         drop this share of the outgoing packets
  --bad-checksum-at T    send wrong checksums from tick T on (the server must report a desync)
  --quit-at T            drop out at tick T (the server must tell the opponent)
  --garbage              now and then send random bytes
  --decline              decline every challenge
  --no-checksum          send no checksums (when playing against a real C64)
  --invite NAME          challenge NAME as soon as the lobby list shows it free
  --human                do not mark this client as a bot in the lobby lists
""");
            return 0;
        }
        try
        {
            var options = BotOptions.Parse(args);
            using var cts = new CancellationTokenSource();
            Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };
            return new BotClient(options).Run(cts.Token);
        }
        catch (ArgumentException e)
        {
            Console.Error.WriteLine(e.Message);
            return 2;
        }
    }
}
