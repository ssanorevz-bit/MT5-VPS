//+------------------------------------------------------------------+
//| DOM_S50IF.mq5                                                    |
//| EA #1 — S50IF_CON + S50 Futures, DOM only, flush 10ms           |
//| v5.1: Futures auto-discover | Tick moved to Tick_TFEX.mq5       |
//+------------------------------------------------------------------+
#property copyright "Quant"
#property version   "5.10"
#property strict
#property description "DOM Collector — S50IF_CON & S50 Futures | flush 10ms | no tick"

//── Config ─────────────────────────────────────────────────────────
#define OUT_FILE        "dom\\dom_s50if.csv"
#define FLUSH_MS        10
#define HEARTBEAT_SEC   30
#define RESYNC_SEC      1800
#define FUT_RESYNC      3000   // re-discover futures ทุก 5 นาที (3000 × 10ms)

//── Globals ─────────────────────────────────────────────────────────
int      g_fh            = INVALID_HANDLE;
ulong    g_init_mcs      = 0;
datetime g_init_sec      = 0;
ulong    g_last_flush    = 0;
datetime g_last_hb       = 0;
datetime g_last_resync   = 0;
long     g_events        = 0;

//── Futures ─────────────────────────────────────────────────────────
string   g_fut[];
int      g_fut_cnt       = 0;
static int s_fut_tick    = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_init_sec    = TimeCurrent();
   g_init_mcs    = GetMicrosecondCount();
   g_last_flush  = g_init_mcs;
   g_last_hb     = g_init_sec;
   g_last_resync = g_init_sec;

   if(!OpenFile()) return INIT_FAILED;

   if(!MarketBookAdd("S50IF_CON"))
     { Print("[S50IF] ERROR: MarketBookAdd(S50IF_CON) failed"); return INIT_FAILED; }

   DiscoverFutures();

   EventSetMillisecondTimer(FLUSH_MS);
   Print("[S50IF] Started | flush=", FLUSH_MS, "ms | futures=", g_fut_cnt, " | file=", OUT_FILE);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   MarketBookRelease("S50IF_CON");
   for(int i = 0; i < g_fut_cnt; i++) MarketBookRelease(g_fut[i]);
   if(g_fh != INVALID_HANDLE)
     { FileFlush(g_fh); FileClose(g_fh); g_fh = INVALID_HANDLE; }
   Print("[S50IF] Stopped. dom_events=", g_events, " | futures=", g_fut_cnt);
  }

//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
  {
   if(symbol != "S50IF_CON" && !IsFutures(symbol)) return;
   if(g_fh == INVALID_HANDLE && !OpenFile()) return;

   MqlBookInfo book[];
   if(!MarketBookGet(symbol, book)) return;
   int sz = ArraySize(book);
   if(sz <= 0) return;

   g_events++;
   string ts     = TimestampUs();
   int    levels = (sz > 20) ? 20 : sz;

   for(int i = 0; i < levels; i++)
     {
      if(i >= ArraySize(book)) break;
      string t = BookType(book[i].type);
      if(t == "") continue;
      FileWrite(g_fh, ts, symbol, t,
                DoubleToString(book[i].price, 2),
                IntegerToString((long)book[i].volume));
     }

   ulong now = GetMicrosecondCount();
   if(now - g_last_flush >= (ulong)FLUSH_MS * 1000)
     { FileFlush(g_fh); g_last_flush = now; }
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();
   if(g_fh != INVALID_HANDLE) FileFlush(g_fh);

   if(now - g_last_hb >= HEARTBEAT_SEC)
     {
      if(g_fh != INVALID_HANDLE)
         FileWrite(g_fh, TimestampUs(), "S50IF_CON", "HEARTBEAT", "", "", "");
      g_last_hb = now;
     }

   if(now - g_last_resync >= RESYNC_SEC)
     { g_init_sec = now; g_init_mcs = GetMicrosecondCount(); g_last_resync = now; }

   // re-discover futures ทุก 5 นาที
   if(++s_fut_tick >= FUT_RESYNC) { DiscoverFutures(); s_fut_tick = 0; }
  }

void OnTick() { }

//+------------------------------------------------------------------+
void DiscoverFutures()
  {
   int total = SymbolsTotal(false), added = 0;
   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      if(!IsS50Future(name) || IsFutures(name)) continue;
      if(MarketBookAdd(name))
        { ArrayResize(g_fut, g_fut_cnt+1); g_fut[g_fut_cnt++] = name; added++; }
     }
   if(added > 0)
      Print("[S50IF] Futures +", added, " contracts. Total=", g_fut_cnt);
  }

bool IsS50Future(const string &name)
  {
   if(StringLen(name) < 5)               return false;
   if(StringSubstr(name, 0, 3) != "S50") return false;
   if(name == "S50IF_CON")               return false;
   string m = StringSubstr(name, 3, 1);
   if(StringFind("FGHJKMNQUVXZ", m) < 0) return false;
   // Options มี month code ต่างกัน และมี strike price ต่อท้าย
   // Futures = S50M26 (6 chars), Options = S50H26C1600 (10+ chars)
   return (StringLen(name) <= 6);
  }

bool IsFutures(const string &sym)
  {
   for(int i = 0; i < g_fut_cnt; i++)
      if(g_fut[i] == sym) return true;
   return false;
  }

//+------------------------------------------------------------------+
bool OpenFile()
  {
   if(g_fh != INVALID_HANDLE) { FileClose(g_fh); g_fh = INVALID_HANDLE; }
   g_fh = FileOpen(OUT_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
   if(g_fh == INVALID_HANDLE)
     {
      g_fh = FileOpen(OUT_FILE, FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
      if(g_fh == INVALID_HANDLE)
        { Print("[S50IF] ERROR opening file: ", GetLastError()); return false; }
      FileWrite(g_fh, "timestamp_us", "symbol", "type", "price", "volume");
      FileFlush(g_fh);
      return true;
     }
   FileSeek(g_fh, 0, SEEK_END);
   return true;
  }

string TimestampUs()
  {
   ulong    e   = GetMicrosecondCount() - g_init_mcs;
   datetime sec = g_init_sec + (datetime)(e / 1000000);
   int      us  = (int)(e % 1000000);
   MqlDateTime dt; TimeToStruct(sec, dt);
   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d.%06d",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, us);
  }

string BookType(ENUM_BOOK_TYPE t)
  {
   switch(t)
     {
      case BOOK_TYPE_SELL:         return "ask";
      case BOOK_TYPE_BUY:          return "bid";
      case BOOK_TYPE_SELL_MARKET:  return "ask_mkt";
      case BOOK_TYPE_BUY_MARKET:   return "bid_mkt";
      default:                     return "";
     }
  }
//+------------------------------------------------------------------+
