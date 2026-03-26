//+------------------------------------------------------------------+
//| DOM_Stocks_A.mq5                                                 |
//| EA #5a — SET50 stocks (~32 ตัว), flush 50ms, no dedup           |
//| v1: Split from DOM_Stocks.mq5, higher-liquidity tier            |
//+------------------------------------------------------------------+
#property copyright "Quant"
#property version   "1.00"
#property strict
#property description "DOM Collector #5a — SET50 stocks | flush 50ms"

#define OUT_FILE        "dom\\dom_stocks_a.csv"
#define FLUSH_MS        50
#define HEARTBEAT_SEC   30
#define RESYNC_SEC      1800

// SET50 stocks (ที่ไม่อยู่ใน DOM_High หรือ DOM_Delta)
string STOCK_LIST[] = {
   "PTT","OR","SCB","KBANK","BBL","CPN","CPF","HMPRO","LH","BEM",
   "EA","TISCO","SAWAD","TIDLOR","GPSC","CRC","BCH","MTC","BTS","AWC",
   "BGRIM","EGCO","RATCH","KKP","BAY","TOP","TCAP","BJC","VGI","KTC",
   "AEONTS","BCP"
};

// Excluded (อยู่ใน DOM_High หรือ DOM_Delta แล้ว)
string EXCLUDED[] = {
   "DELTA",
   "GULF","BDMS","HANA","BANPU","PTTEP","IVL","AOT","KTB","KCE",
   "TTB","MINT","SCGP","IRPC","SCC","WHA","TFG","BH","TRUE",
   "CPALL","ADVANC","PTTGC"
};

int      g_fh          = INVALID_HANDLE;
ulong    g_init_mcs    = 0;
datetime g_init_sec    = 0;
ulong    g_last_flush  = 0;
datetime g_last_hb     = 0;
datetime g_last_resync = 0;
long     g_events      = 0;
string   g_subs[];
int      g_sub_count   = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_init_sec    = TimeCurrent();
   g_init_mcs    = GetMicrosecondCount();
   g_last_flush  = g_init_mcs;
   g_last_hb     = g_init_sec;
   g_last_resync = g_init_sec;

   if(!OpenFile()) return INIT_FAILED;

   int ok = 0, n = ArraySize(STOCK_LIST);
   for(int i = 0; i < n; i++)
     {
      string s = STOCK_LIST[i];
      if(IsExcluded(s) || IsSubscribed(s)) continue;
      if(SymbolSelect(s, true) && MarketBookAdd(s))
        { ArrayResize(g_subs, g_sub_count+1); g_subs[g_sub_count++] = s; ok++; }
     }

   EventSetMillisecondTimer(FLUSH_MS);
   Print("[STOCKS_A] Started | ", ok, " symbols | flush=", FLUSH_MS, "ms | file=", OUT_FILE);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < g_sub_count; i++) MarketBookRelease(g_subs[i]);
   if(g_fh != INVALID_HANDLE)
     { FileFlush(g_fh); FileClose(g_fh); g_fh = INVALID_HANDLE; }
   Print("[STOCKS_A] Stopped. events=", g_events);
  }

void OnBookEvent(const string &symbol)
  {
   if(!IsSubscribed(symbol)) return;
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

void OnTimer()
  {
   datetime now = TimeCurrent();
   if(g_fh != INVALID_HANDLE) FileFlush(g_fh);
   if(now - g_last_hb >= HEARTBEAT_SEC)
     {
      if(g_fh != INVALID_HANDLE)
         FileWrite(g_fh, TimestampUs(), "STOCKS_A", "HEARTBEAT", "", "", "");
      g_last_hb = now;
     }
   if(now - g_last_resync >= RESYNC_SEC)
     { g_init_sec = now; g_init_mcs = GetMicrosecondCount(); g_last_resync = now; }
  }

void OnTick() { }

bool IsExcluded(const string &sym)
  { for(int i=0;i<ArraySize(EXCLUDED);i++) if(EXCLUDED[i]==sym) return true; return false; }

bool IsSubscribed(const string &sym)
  { for(int i=0;i<g_sub_count;i++) if(g_subs[i]==sym) return true; return false; }

bool OpenFile()
  {
   if(g_fh != INVALID_HANDLE) { FileClose(g_fh); g_fh = INVALID_HANDLE; }
   g_fh = FileOpen(OUT_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
   if(g_fh == INVALID_HANDLE)
     {
      g_fh = FileOpen(OUT_FILE, FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
      if(g_fh == INVALID_HANDLE)
        { Print("[STOCKS_A] ERROR opening file: ", GetLastError()); return false; }
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
//+------------------------------------------------------------------+
