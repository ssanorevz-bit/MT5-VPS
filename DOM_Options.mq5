//+------------------------------------------------------------------+
//| DOM_Options.mq5                                                  |
//| EA #4 — S50 Options auto-discover, flush 100ms, no dedup        |
//| v4: volume_dbl, file append, microsecond, heartbeat, re-sync    |
//+------------------------------------------------------------------+
#property copyright "Quant"
#property version   "4.00"
#property strict
#property description "DOM Collector #4 — S50 Options auto-discover | flush 100ms"

#define OUT_FILE        "dom\\dom_options.csv"
#define FLUSH_MS        100
#define HEARTBEAT_SEC   30
#define RESYNC_SEC      1800

int      g_fh            = INVALID_HANDLE;
ulong    g_init_mcs      = 0;
datetime g_init_sec      = 0;
ulong    g_last_flush    = 0;
datetime g_last_hb       = 0;
datetime g_last_resync   = 0;
long     g_events        = 0;
string   g_symbols[];
int      g_sym_count     = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_init_sec    = TimeCurrent();
   g_init_mcs    = GetMicrosecondCount();
   g_last_flush  = g_init_mcs;
   g_last_hb     = g_init_sec;
   g_last_resync = g_init_sec;

   if(!OpenFile()) return INIT_FAILED;
   DiscoverAndSubscribe();
   EventSetMillisecondTimer(FLUSH_MS);
   Print("[OPTIONS] Started | ", g_sym_count, " series | flush=", FLUSH_MS, "ms");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < g_sym_count; i++) MarketBookRelease(g_symbols[i]);
   if(g_fh != INVALID_HANDLE)
     { FileFlush(g_fh); FileClose(g_fh); g_fh = INVALID_HANDLE; }
   Print("[OPTIONS] Stopped. events=", g_events);
  }

//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
  {
   if(!IsTracked(symbol)) return;
   if(g_fh == INVALID_HANDLE && !OpenFile()) return;
   MqlBookInfo book[];
   if(!MarketBookGet(symbol, book)) return;
   int sz = ArraySize(book);
   if(sz <= 0) return;

   g_events++;
   string ts = TimestampUs();
   int levels = (sz > 20) ? 20 : sz;

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
         FileWrite(g_fh, TimestampUs(), "OPTIONS", "HEARTBEAT", "", "", "");
      g_last_hb = now;
     }

   if(now - g_last_resync >= RESYNC_SEC)
     { g_init_sec = now; g_init_mcs = GetMicrosecondCount(); g_last_resync = now; }

   // re-discover options ทุก 5 นาที (300 วินาที / tick 100ms = ~3000 ticks)
   static int s_tick = 0;
   if(++s_tick >= 3000)  { DiscoverAndSubscribe(); s_tick = 0; }
  }

//+------------------------------------------------------------------+
void DiscoverAndSubscribe()
  {
   int total = SymbolsTotal(false), added = 0;
   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      if(!IsS50Option(name) || IsTracked(name)) continue;
      if(MarketBookAdd(name))
        { ArrayResize(g_symbols, g_sym_count+1); g_symbols[g_sym_count++] = name; added++; }
     }
   if(added > 0) Print("[OPTIONS] +", added, " series. Total=", g_sym_count);
  }

bool IsS50Option(const string &name)
  {
   if(StringLen(name) < 9)               return false;
   if(StringSubstr(name,0,3) != "S50")   return false;
   string m = StringSubstr(name,3,1);
   if(StringFind("HJKMNQUVXZ",m) < 0)    return false;
   if(StringFind(name,"C",5)<0 && StringFind(name,"P",5)<0) return false;
   return true;
  }

bool IsTracked(const string &sym)
  {
   for(int i=0;i<g_sym_count;i++) if(g_symbols[i]==sym) return true;
   return false;
  }

bool OpenFile()
  {
   if(g_fh != INVALID_HANDLE) { FileClose(g_fh); g_fh = INVALID_HANDLE; }
   g_fh = FileOpen(OUT_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
   if(g_fh == INVALID_HANDLE)
     {
      g_fh = FileOpen(OUT_FILE, FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
      if(g_fh == INVALID_HANDLE)
        { Print("[OPTIONS] ERROR opening file: ", GetLastError()); return false; }
      FileWrite(g_fh, "timestamp_us","symbol","type","price","volume");
      FileFlush(g_fh); return true;
     }
   FileSeek(g_fh, 0, SEEK_END); return true;
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

void OnTick() { }
//+------------------------------------------------------------------+
