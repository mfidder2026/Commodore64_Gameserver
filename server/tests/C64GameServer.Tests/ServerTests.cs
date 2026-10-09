using System.Net;
using C64GameServer.Core;
using C64GameServer.Games;
using C64GameServer.Protocol;

namespace C64GameServer.Tests;

internal sealed class FakeTransport : ITransport
{
    public readonly List<(IPEndPoint To, byte[] Data)> Sent = [];

    public void Send(IPEndPoint to, ReadOnlySpan<byte> message) => Sent.Add((to, message.ToArray()));

    public List<byte[]> To(IPEndPoint ep, byte type) =>
        Sent.Where(s => s.To.Equals(ep) && s.Data[0] == type).Select(s => s.Data).ToList();

    public byte[]? Last(IPEndPoint ep, byte type) => To(ep, type).LastOrDefault();

    public void Clear() => Sent.Clear();
}

internal sealed class Harness
{
    public readonly FakeTransport Net = new();
    public readonly ServerConfig Config = new() { AutoPair = true, Bots = [] };
    public readonly ServerCore Core;
    public DateTime Now = new(2026, 10, 3, 12, 0, 0, DateTimeKind.Utc);

    public Harness()
    {
        Core = new ServerCore(Config, Net, GameRegistry.FromConfig(Config), new EventLog(), Now, new Random(1));
    }

    public static IPEndPoint Ep(int n, int port = 0) => new(IPAddress.Parse($"192.168.1.{n}"), port == 0 ? 50000 + n : port);

    public void Recv(IPEndPoint from, params byte[] data) => Core.HandleDatagram(from, data, Now);

    public void Advance(double ms)
    {
        // tick in 20 ms steps, like the server loop
        var end = Now.AddMilliseconds(ms);
        while (Now < end)
        {
            Now = Now.AddMilliseconds(Math.Min(20, (end - Now).TotalMilliseconds));
            Core.Tick(Now);
        }
    }

    public void Hello(IPEndPoint ep, string nick, byte game = 1) => Recv(ep, Messages.Hello(game, 1, nick));

    /// <summary>Two players in a Wizard of Wor session; returns the session id.</summary>
    public byte StartGame(IPEndPoint a, IPEndPoint b)
    {
        Hello(a, "ANNA");
        Hello(b, "BERT");
        Advance(20);
        Recv(a, MsgType.Accept, Net.Last(a, MsgType.Challenge)![1]);
        Recv(b, MsgType.Accept, Net.Last(b, MsgType.Challenge)![1]);
        var start = Net.Last(a, MsgType.Start)!;
        Recv(a, MsgType.StartAck, start[1]);
        Recv(b, MsgType.StartAck, start[1]);
        return start[1];
    }

    public static byte[] Input(byte session, ushort newest, ushort chkTick, ushort chk)
    {
        var m = new byte[WizardOfWorModule.InputLength];
        m[0] = WizardOfWorModule.Input;
        m[1] = session;
        m[2] = (byte)newest; m[3] = (byte)(newest >> 8);
        m[4] = (byte)chkTick; m[5] = (byte)(chkTick >> 8);
        m[6] = (byte)chk; m[7] = (byte)(chk >> 8);
        for (int i = 8; i < m.Length; i++) m[i] = (byte)(0xE0 | i);
        return m;
    }
}

public class FrameTests
{
    [Fact]
    public void Hello_round_trip()
    {
        var m = Messages.Hello(1, 1, "ERIK");
        Assert.Equal("01 01 01 01 04 45 52 49 4b", Messages.Hex(m));
        var h = Messages.ParseHello(m)!;
        Assert.Equal(("ERIK", (byte)1, (byte)1), (h.Nick, h.GameId, h.GameVersion));
    }

    [Theory]
    [InlineData(new byte[] { 0x01 })]
    [InlineData(new byte[] { 0x01, 1, 1, 1, 0 })]              // empty nickname
    [InlineData(new byte[] { 0x01, 1, 1, 1, 9, 65, 65, 65, 65, 65, 65, 65, 65, 65 })] // 9 characters
    [InlineData(new byte[] { 0x01, 1, 1, 1, 4, 65, 66 })]       // too short
    public void Malformed_hello_gives_null(byte[] m) => Assert.Null(Messages.ParseHello(m));

    [Fact]
    public void Start_contains_slot_and_parameters()
    {
        var m = Messages.Start(7, 1, 2, [0xAA, 0xBB, 4, 60]);
        Assert.Equal("08 07 01 02 04 aa bb 04 3c", Messages.Hex(m));
    }

    [Fact]
    public void Valid_nicknames() =>
        Assert.True(Messages.IsValidNick("A1") && !Messages.IsValidNick("anna") && !Messages.IsValidNick("TOOLONGNAME"));
}

public class LobbyTests
{
    [Fact]
    public void Hello_is_welcomed_and_repeated_hello_gets_the_same_id()
    {
        var h = new Harness();
        var a = Harness.Ep(10);
        h.Hello(a, "ANNA");
        var w1 = h.Net.Last(a, MsgType.Welcome)!;
        h.Hello(a, "ANNA");
        var w2 = h.Net.Last(a, MsgType.Welcome)!;
        Assert.Equal(w1[2], w2[2]);
        Assert.Single(h.Core.Clients);
    }

    [Theory]
    [InlineData(2, 1, 1, "ANNA", RejectReason.Version)]
    [InlineData(1, 9, 1, "ANNA", RejectReason.UnknownGame)]
    [InlineData(1, 1, 7, "ANNA", RejectReason.Version)]
    [InlineData(1, 1, 1, "anna", RejectReason.BadName)]
    public void Invalid_hello_is_rejected(byte proto, byte game, byte version, string nick, RejectReason reason)
    {
        var h = new Harness();
        var a = Harness.Ep(10);
        var m = Messages.Hello(game, version, nick);
        m[1] = proto;
        h.Recv(a, m);
        Assert.Equal((byte)reason, h.Net.Last(a, MsgType.Reject)![1]);
        Assert.Empty(h.Core.Clients);
    }

    [Fact]
    public void A_name_in_use_from_another_machine_is_rejected_but_the_same_machine_takes_over()
    {
        var h = new Harness();
        h.Hello(Harness.Ep(10), "ANNA");
        h.Hello(Harness.Ep(11), "ANNA");
        Assert.Equal((byte)RejectReason.NameInUse, h.Net.Last(Harness.Ep(11), MsgType.Reject)![1]);

        var newPort = Harness.Ep(10, 60000); // the same C64 with a new socket
        h.Hello(newPort, "ANNA");
        Assert.NotNull(h.Net.Last(newPort, MsgType.Welcome));
        Assert.Equal(newPort, h.Core.Clients.Single().EndPoint);
    }

    [Fact]
    public void Two_players_are_challenged_and_start_after_both_accept()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        h.Hello(a, "ANNA");
        h.Hello(b, "BERT");
        h.Advance(20);
        var cha = h.Net.Last(a, MsgType.Challenge)!;
        var chb = h.Net.Last(b, MsgType.Challenge)!;
        Assert.Equal("BERT", System.Text.Encoding.ASCII.GetString(cha, 3, cha[2]));
        Assert.Equal("ANNA", System.Text.Encoding.ASCII.GetString(chb, 3, chb[2]));

        h.Recv(a, MsgType.Accept, cha[1]);
        Assert.Null(h.Net.Last(a, MsgType.Start));
        h.Recv(b, MsgType.Accept, chb[1]);
        var sa = h.Net.Last(a, MsgType.Start)!;
        var sb = h.Net.Last(b, MsgType.Start)!;
        Assert.Equal((0, 1), (sa[2], sb[2]));        // slots
        Assert.Equal(4, sa[4]);                       // 4 start parameters
        Assert.Equal(sa[5..], sb[5..]);               // the same seeds for both
        Assert.NotEqual(0, sa[6]);                    // LFSR seed never 0

        // START is repeated until confirmed
        h.Net.Clear();
        h.Advance(300);
        Assert.NotEmpty(h.Net.To(a, MsgType.Start));
        h.Recv(a, MsgType.StartAck, sa[1]);
        h.Recv(b, MsgType.StartAck, sb[1]);
        h.Net.Clear();
        h.Advance(1000);
        Assert.Empty(h.Net.To(a, MsgType.Start));
    }

    [Fact]
    public void A_challenge_is_repeated_until_answered()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        h.Hello(a, "ANNA");
        h.Hello(b, "BERT");
        h.Advance(20);
        h.Net.Clear();
        h.Advance(1100);
        Assert.True(h.Net.To(a, MsgType.Challenge).Count >= 2);
    }

    [Fact]
    public void After_a_decline_the_same_players_are_not_paired_for_a_minute()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        h.Hello(a, "ANNA");
        h.Hello(b, "BERT");
        h.Advance(20);
        h.Recv(b, MsgType.Decline, h.Net.Last(b, MsgType.Challenge)![1]);
        Assert.Equal((byte)CancelReason.Declined, h.Net.Last(a, MsgType.ChallengeCancelled)![2]);
        Assert.All(h.Core.Clients, c => Assert.Equal(ClientState.Lobby, c.State));

        h.Net.Clear();
        for (int i = 0; i < 50; i++) // keep them alive for 50 s
        {
            h.Advance(1000);
            h.Recv(a, Messages.Ping(1));
            h.Recv(b, Messages.Ping(1));
        }
        Assert.Empty(h.Net.To(a, MsgType.Challenge));
        for (int i = 0; i < 12; i++)
        {
            h.Advance(1000);
            h.Recv(a, Messages.Ping(1));
            h.Recv(b, Messages.Ping(1));
        }
        Assert.NotEmpty(h.Net.To(a, MsgType.Challenge));
    }

    [Fact]
    public void An_unanswered_challenge_is_cancelled_after_30_seconds()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        h.Hello(a, "ANNA");
        h.Hello(b, "BERT");
        h.Advance(20);
        h.Recv(a, MsgType.Accept, h.Net.Last(a, MsgType.Challenge)![1]);
        for (int i = 0; i < 31; i++)
        {
            h.Advance(1000);
            h.Recv(a, Messages.Ping(1));
            h.Recv(b, Messages.Ping(1));
        }
        Assert.Equal((byte)CancelReason.Timeout, h.Net.Last(a, MsgType.ChallengeCancelled)![2]);
    }

    [Fact]
    public void A_silent_client_is_removed_after_10_seconds()
    {
        var h = new Harness();
        h.Hello(Harness.Ep(10), "ANNA");
        h.Advance(9000);
        Assert.Single(h.Core.Clients);
        h.Advance(1100);
        Assert.Empty(h.Core.Clients);
    }

    [Fact]
    public void Ping_gets_pong_with_the_same_token()
    {
        var h = new Harness();
        var a = Harness.Ep(10);
        h.Hello(a, "ANNA");
        h.Recv(a, Messages.Ping(0x1234));
        Assert.Equal(Messages.Pong(0x1234), h.Net.Last(a, MsgType.Pong));
    }

    [Fact]
    public void The_lobby_reports_the_number_of_waiting_players()
    {
        var h = new Harness();
        var a = Harness.Ep(10);
        h.Hello(a, "ANNA");
        h.Advance(40);
        Assert.Equal(1, h.Net.Last(a, MsgType.Lobby)![1]);
    }
}

public class WizardOfWorTests
{
    [Fact]
    public void Input_is_relayed_unchanged_to_the_opponent()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        byte s = h.StartGame(a, b);
        var input = Harness.Input(s, 20, 0xFFFF, 0);
        h.Recv(a, input);
        Assert.Equal(input, h.Net.Last(b, WizardOfWorModule.Input));
        Assert.Null(h.Net.Last(a, WizardOfWorModule.Input));
    }

    [Fact]
    public void Input_of_another_session_is_dropped()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        byte s = h.StartGame(a, b);
        h.Recv(a, Harness.Input((byte)(s + 1), 20, 0xFFFF, 0));
        Assert.Null(h.Net.Last(b, WizardOfWorModule.Input));
    }

    [Fact]
    public void Equal_checksums_keep_the_session_and_different_ones_end_it_with_desync()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        byte s = h.StartGame(a, b);
        h.Recv(a, Harness.Input(s, 70, 64, 0x1234));
        h.Recv(b, Harness.Input(s, 70, 64, 0x1234));
        Assert.Single(h.Core.Sessions);

        h.Recv(a, Harness.Input(s, 134, 128, 0x1111));
        h.Recv(b, Harness.Input(s, 134, 128, 0x2222));
        Assert.Empty(h.Core.Sessions);
        Assert.Equal((byte)EndReason.Desync, h.Net.Last(a, MsgType.SessionEnd)![2]);
        Assert.Equal((byte)EndReason.Desync, h.Net.Last(b, MsgType.SessionEnd)![2]);
        Assert.All(h.Core.Clients, c => Assert.Equal(ClientState.Lobby, c.State));
    }

    [Fact]
    public void A_player_that_goes_silent_ends_the_session_with_opponent_left()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        byte s = h.StartGame(a, b);
        for (int i = 0; i < 11; i++)
        {
            h.Advance(1000);
            h.Recv(a, Harness.Input(s, (ushort)(i * 60), 0xFFFF, 0)); // only A keeps sending
        }
        Assert.NotNull(h.Net.Last(a, MsgType.OpponentLeft));
        Assert.Empty(h.Core.Sessions);
        Assert.Equal(ClientState.Lobby, h.Core.Clients.Single().State);
    }

    [Fact]
    public void A_player_that_still_answers_pings_but_sends_no_input_ends_the_session()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        byte s = h.StartGame(a, b);
        for (int i = 0; i < 11; i++)
        {
            h.Advance(1000);
            h.Recv(a, Harness.Input(s, (ushort)(i * 60), 0xFFFF, 0));
            h.Recv(b, Messages.Ping(1)); // B is alive but plays no more
        }
        Assert.NotNull(h.Net.Last(a, MsgType.OpponentLeft));
        Assert.Empty(h.Core.Sessions);
        Assert.All(h.Core.Clients, c => Assert.NotEqual(ClientState.InSession, c.State)); // back in the lobby (may be challenged again)
    }

    [Fact]
    public void Game_over_brings_both_back_to_the_lobby()
    {
        var h = new Harness();
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        byte s = h.StartGame(a, b);
        h.Recv(a, Messages.SessionEnd(s, EndReason.Finished));
        Assert.Equal((byte)EndReason.Finished, h.Net.Last(b, MsgType.SessionEnd)![2]);
        Assert.All(h.Core.Clients, c => Assert.Equal(ClientState.Lobby, c.State));
    }
}

public class PlatformTests
{
    [Fact]
    public void A_relay_game_from_the_configuration_needs_no_code()
    {
        var h = new Harness(); // server.json default: game 2 = "Relay demo", module "relay"
        var (a, b) = (Harness.Ep(10), Harness.Ep(11));
        h.Hello(a, "ANNA", game: 2);
        h.Hello(b, "BERT", game: 2);
        h.Advance(20);
        h.Recv(a, MsgType.Accept, h.Net.Last(a, MsgType.Challenge)![1]);
        h.Recv(b, MsgType.Accept, h.Net.Last(b, MsgType.Challenge)![1]);
        byte s = h.Net.Last(a, MsgType.Start)![1];
        byte[] msg = [0x91, s, 1, 2, 3];
        h.Recv(b, msg);
        Assert.Equal(msg, h.Net.Last(a, 0x91));
    }

    [Fact]
    public void Players_of_different_games_are_not_paired()
    {
        var h = new Harness();
        h.Hello(Harness.Ep(10), "ANNA", game: 1);
        h.Hello(Harness.Ep(11), "BERT", game: 2);
        h.Advance(100);
        Assert.Empty(h.Core.Challenges);
    }

    [Fact]
    public void Two_sessions_run_independently()
    {
        var h = new Harness();
        byte s1 = h.StartGame(Harness.Ep(10), Harness.Ep(11));
        h.Hello(Harness.Ep(12), "CARL");
        h.Hello(Harness.Ep(13), "DORA");
        h.Advance(20);
        h.Recv(Harness.Ep(12), MsgType.Accept, h.Net.Last(Harness.Ep(12), MsgType.Challenge)![1]);
        h.Recv(Harness.Ep(13), MsgType.Accept, h.Net.Last(Harness.Ep(13), MsgType.Challenge)![1]);
        byte s2 = h.Net.Last(Harness.Ep(12), MsgType.Start)![1];
        Assert.NotEqual(s1, s2);
        var input = Harness.Input(s2, 5, 0xFFFF, 0);
        h.Recv(Harness.Ep(12), input);
        Assert.Equal(input, h.Net.Last(Harness.Ep(13), WizardOfWorModule.Input));
        Assert.Null(h.Net.Last(Harness.Ep(11), WizardOfWorModule.Input));
    }

    [Fact]
    public void Garbage_never_crashes_the_server()
    {
        var h = new Harness();
        var rnd = new Random(42);
        byte s = h.StartGame(Harness.Ep(10), Harness.Ep(11));
        for (int i = 0; i < 20000; i++)
        {
            var len = rnd.Next(0, 300);
            var data = new byte[len];
            rnd.NextBytes(data);
            if (len > 1 && rnd.Next(4) == 0) data[1] = s;
            var from = rnd.Next(3) == 0 ? Harness.Ep(10 + rnd.Next(2)) : Harness.Ep(rnd.Next(1, 250), rnd.Next(1, 65535));
            h.Recv(from, data);
            if (i % 100 == 0) h.Advance(20);
        }
        Assert.True(h.Core.InvalidDatagrams > 0);
    }
}

/// <summary>The lobby without auto pairing: the players see who is online and invite an opponent.</summary>
public class ChooseOpponentTests
{
    private static Harness Lobby()
    {
        var h = new Harness();
        h.Config.AutoPair = false;
        return h;
    }

    private static byte IdOf(Harness h, string nick) => h.Core.Clients.Single(c => c.Nick == nick).Id;

    private static List<PlayerEntry> ListOf(Harness h, IPEndPoint ep)
    {
        var all = new List<PlayerEntry>();
        var pages = h.Net.To(ep, MsgType.Players).Select(m => Messages.ParsePlayers(m)!.Value).ToList();
        var lastTotal = pages[^1].Total;
        // the newest complete list: the last pages starting from the last page with index 0
        int from = pages.FindLastIndex(p => p.First == 0);
        foreach (var p in pages.Skip(from)) all.AddRange(p.Entries);
        Assert.Equal(lastTotal, all.Count);
        return all;
    }

    [Fact]
    public void Hello_can_say_bot()
    {
        var m = Messages.Hello(1, 1, "WORLUK", bot: true);
        Assert.Equal("01 01 01 01 06 57 4f 52 4c 55 4b 01", Messages.Hex(m));
        Assert.True(Messages.ParseHello(m)!.Bot);
        Assert.False(Messages.ParseHello(Messages.Hello(1, 1, "ERIK"))!.Bot);
    }

    [Fact]
    public void Players_round_trip()
    {
        var m = Messages.Players(3, 0, [new PlayerEntry(4, PlayerFlags.Bot | PlayerFlags.Playing, "GARWOR")]);
        Assert.Equal("10 03 00 01 04 05 06 47 41 52 57 4f 52", Messages.Hex(m));
        var p = Messages.ParsePlayers(m)!.Value;
        Assert.Equal((3, 0, "GARWOR", (byte)5), (p.Total, p.First, p.Entries[0].Nick, p.Entries[0].Flags));
        Assert.Null(Messages.ParsePlayers(m.AsSpan(0, m.Length - 1)));
    }

    [Fact]
    public void Without_auto_pairing_nobody_is_challenged()
    {
        var h = Lobby();
        h.Hello(Harness.Ep(10), "ANNA");
        h.Hello(Harness.Ep(11), "BERT");
        h.Advance(2000);
        Assert.Empty(h.Core.Challenges);
        Assert.Null(h.Net.Last(Harness.Ep(10), MsgType.Challenge));
    }

    [Fact]
    public void The_list_shows_the_others_people_first_with_kind_and_state()
    {
        var h = Lobby();
        var a = Harness.Ep(10);
        h.Recv(Harness.Ep(20), Messages.Hello(1, 1, "WORLUK", bot: true));
        h.Hello(a, "ANNA");
        h.Hello(Harness.Ep(11), "BERT");
        h.Hello(Harness.Ep(12), "CARL");
        h.Advance(300);
        var list = ListOf(h, a);
        Assert.Equal(["BERT", "CARL", "WORLUK"], list.Select(e => e.Nick));
        Assert.Equal([PlayerFlags.Free, PlayerFlags.Free, PlayerFlags.Bot], list.Select(e => e.Flags));
        Assert.Empty(h.Net.To(Harness.Ep(20), MsgType.Players)); // bots get no lists

        // BERT invites CARL: both busy; then they play
        h.Recv(Harness.Ep(11), Messages.Invite(IdOf(h, "CARL"), 1));
        h.Advance(300);
        Assert.Equal([PlayerFlags.Busy, PlayerFlags.Busy], ListOf(h, a).Take(2).Select(e => e.Flags));
        h.Recv(Harness.Ep(12), MsgType.Accept, h.Net.Last(Harness.Ep(12), MsgType.Challenge)![1]);
        h.Advance(300);
        Assert.Equal([PlayerFlags.Playing, PlayerFlags.Playing], ListOf(h, a).Take(2).Select(e => e.Flags));
    }

    [Fact]
    public void A_long_list_comes_in_pages_of_six()
    {
        var h = Lobby();
        var a = Harness.Ep(10);
        h.Hello(a, "ANNA");
        for (int i = 0; i < 20; i++) h.Hello(Harness.Ep(100 + i), "P" + i);
        h.Advance(1100);
        var list = ListOf(h, a);
        Assert.Equal(ProtocolConst.MaxListed, list.Count);
        Assert.All(h.Net.To(a, MsgType.Players), m => Assert.True(m.Length <= 128));
    }

    [Fact]
    public void Invite_challenges_only_the_target_and_starts_after_its_accept()
    {
        var h = Lobby();
        var a = Harness.Ep(10);
        var b = Harness.Ep(11);
        h.Hello(a, "ANNA");
        h.Hello(b, "BERT");
        h.Recv(a, Messages.Invite(IdOf(h, "BERT"), 1));
        var ch = h.Net.Last(b, MsgType.Challenge)!;
        Assert.Equal("ANNA", System.Text.Encoding.ASCII.GetString(ch, 3, ch[2]));
        Assert.Null(h.Net.Last(a, MsgType.Challenge)); // the inviter has accepted already
        h.Recv(a, Messages.Invite(IdOf(h, "BERT"), 1)); // a repeat changes nothing
        Assert.Single(h.Core.Challenges);
        h.Recv(b, MsgType.Accept, ch[1]);
        Assert.Equal(0, h.Net.Last(a, MsgType.Start)![2]); // the inviter is slot 0 (player 1)
        Assert.Equal(1, h.Net.Last(b, MsgType.Start)![2]);
    }

    [Fact]
    public void Inviting_a_busy_player_says_not_available()
    {
        var h = Lobby();
        var a = Harness.Ep(10);
        h.Hello(a, "ANNA");
        h.Hello(Harness.Ep(11), "BERT");
        h.Hello(Harness.Ep(12), "CARL");
        h.Recv(Harness.Ep(11), Messages.Invite(IdOf(h, "CARL"), 1));
        h.Recv(a, Messages.Invite(IdOf(h, "CARL"), 1));
        Assert.Equal([MsgType.ChallengeCancelled, 0, (byte)CancelReason.NotAvailable], h.Net.Last(a, MsgType.ChallengeCancelled));
        h.Recv(a, Messages.Invite(99, 2)); // unknown player
        Assert.Equal(2, h.Net.To(a, MsgType.ChallengeCancelled).Count);
    }

    [Fact]
    public void The_inviter_can_withdraw_and_the_target_can_decline()
    {
        var h = Lobby();
        var a = Harness.Ep(10);
        var b = Harness.Ep(11);
        h.Hello(a, "ANNA");
        h.Hello(b, "BERT");
        h.Recv(a, Messages.Invite(IdOf(h, "BERT"), 1));
        h.Recv(a, MsgType.Decline, 0); // withdraw
        Assert.Empty(h.Core.Challenges);
        Assert.NotNull(h.Net.Last(b, MsgType.ChallengeCancelled));

        h.Recv(a, Messages.Invite(IdOf(h, "BERT"), 2)); // a new invite (new sequence number) works at once
        h.Recv(b, MsgType.Decline, h.Net.Last(b, MsgType.Challenge)![1]);
        Assert.Empty(h.Core.Challenges);
        Assert.Equal((byte)CancelReason.Declined, h.Net.Last(a, MsgType.ChallengeCancelled)![2]);
        Assert.All(h.Core.Clients, c => Assert.Equal(ClientState.Lobby, c.State));
    }
}

public class BubbleBobbleTests
{
    private const byte Game = 3;

    private static byte StartBubbleBobble(Harness h, IPEndPoint a, IPEndPoint b)
    {
        h.Hello(a, "ALICE", Game);
        h.Hello(b, "BOB", Game);
        h.Advance(20);
        h.Recv(a, MsgType.Accept, h.Net.Last(a, MsgType.Challenge)![1]);
        h.Recv(b, MsgType.Accept, h.Net.Last(b, MsgType.Challenge)![1]);
        var start = h.Net.Last(a, MsgType.Start)!;
        h.Recv(a, MsgType.StartAck, start[1]);
        h.Recv(b, MsgType.StartAck, start[1]);
        return start[1];
    }

    private static byte[] Input(byte session, ushort newest, ushort chkTick, ushort chk)
    {
        var m = new byte[BubbleBobbleModule.InputLength];
        m[0] = BubbleBobbleModule.Input;
        m[1] = session;
        m[2] = (byte)newest; m[3] = (byte)(newest >> 8);
        m[4] = (byte)chkTick; m[5] = (byte)(chkTick >> 8);
        m[6] = (byte)chk; m[7] = (byte)(chk >> 8);
        for (int i = 8; i < m.Length; i++) m[i] = 0x1F;
        return m;
    }

    [Fact]
    public void Start_has_a_non_zero_seed_and_the_input_delay()
    {
        var h = new Harness();
        StartBubbleBobble(h, Harness.Ep(1), Harness.Ep(2));
        var start = h.Net.Last(Harness.Ep(1), MsgType.Start)!;
        Assert.Equal(3, start[4]);                       // three parameters
        Assert.NotEqual(0, start[5] | start[6] << 8);    // seed
        Assert.Equal(2, start[7]);                       // input delay over UDP
    }

    [Fact]
    public void A_WiC64_player_gets_the_longer_input_delay()
    {
        var h = new Harness();
        var wic = new IPEndPoint(IPAddress.Parse("192.168.1.9").MapToIPv6(), 50000);   // TCP client
        StartBubbleBobble(h, Harness.Ep(1), wic);
        Assert.Equal(4, h.Net.Last(Harness.Ep(1), MsgType.Start)![7]);
    }

    [Fact]
    public void Padded_input_is_relayed_without_the_padding()
    {
        var h = new Harness();
        byte s = StartBubbleBobble(h, Harness.Ep(1), Harness.Ep(2));
        var padded = Input(s, 10, 0xFFFF, 0).Concat(new byte[30]).ToArray();   // a raw Ethernet frame
        h.Recv(Harness.Ep(1), padded);
        Assert.Equal(BubbleBobbleModule.InputLength, h.Net.Last(Harness.Ep(2), BubbleBobbleModule.Input)!.Length);
    }

    [Fact]
    public void A_player_may_stay_silent_while_loading_the_game()
    {
        var h = new Harness();
        StartBubbleBobble(h, Harness.Ep(1), Harness.Ep(2));
        h.Advance(60_000);                               // a 1541 needs about a minute
        Assert.Single(h.Core.Sessions);
        Assert.Equal(2, h.Core.Clients.Count);
    }

    [Fact]
    public void Loading_for_too_long_ends_the_session()
    {
        var h = new Harness();
        byte s = StartBubbleBobble(h, Harness.Ep(1), Harness.Ep(2));
        for (int t = 0; t < 160; t++)                    // ALICE plays, BOB never starts
        {
            h.Recv(Harness.Ep(1), Input(s, (ushort)t, 0xFFFF, 0));
            h.Advance(1000);
        }
        Assert.Empty(h.Core.Sessions);
    }

    [Fact]
    public void Different_checksums_end_the_session_with_desync()
    {
        var h = new Harness();
        byte s = StartBubbleBobble(h, Harness.Ep(1), Harness.Ep(2));
        h.Recv(Harness.Ep(1), Input(s, 66, 64, 0x1234));
        h.Recv(Harness.Ep(2), Input(s, 66, 64, 0x1234));
        Assert.Single(h.Core.Sessions);
        h.Recv(Harness.Ep(1), Input(s, 130, 128, 0x1111));
        h.Recv(Harness.Ep(2), Input(s, 130, 128, 0x2222));
        Assert.Empty(h.Core.Sessions);
        Assert.Equal((byte)EndReason.Desync, h.Net.Last(Harness.Ep(1), MsgType.SessionEnd)![2]);
    }
}
