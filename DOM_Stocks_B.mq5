//+------------------------------------------------------------------+
//| DOM_Stocks_B.mq5                                                 |
//| EA #5b — Non-SET50 stocks (~103 ตัว), flush 100ms, no dedup     |
//| v1: Split from DOM_Stocks.mq5, lower-liquidity tier             |
//+------------------------------------------------------------------+
#property copyright "Quant"
#property version   "1.00"
#property strict
#property description "DOM Collector #5b — Non-SET50 stocks | flush 100ms"

#define OUT_FILE        "dom_stocks_b.csv"
#define FLUSH_MS        100
#define HEARTBEAT_SEC   30
#define RESYNC_SEC      1800

// Non-SET50 stocks (ที่ไม่อยู่ใน DOM_High, DOM_Delta, DOM_Stocks_A)
string STOCK_LIST[] = {
   "THAI","GUNKUL","SPRC","AMATA","BA","ICHI","CHG","TU","PTG","CENTEL",
   "OSP","CK","CBG","STA","ERW","M","THCOM","BCPG","AP","SIRI",
   "AAV","TOA","PSL","STGT","DIF","GFPT","EASTW","BAM","GLOBAL",
   "PLANB","JMT","JAS","NER","PRM","CPNREIT","QH","MAJOR","JMART",
   "SPALI","WHAUP","TVO","INSET","HUMAN","EPG","TTW","CKP","STPI",
   "TTA","TASCO","MEGA","ORI","SINGER","WHART","SISB","BLA",
   "TQM","BPP","TPIPL","TPCH","FORTH","THANI","SUPER","SPCG","BEAUTY",
   "THG","TKN","TPIPP","MBK","BLAND","MASTER","ITEL","ASIAN","BEC",
   "SUSCO","PSH","UNIQ","LHFG","VIBHA","ITD","KLINIQ","LPN",
   "SAMART","S","SGP","TNP","RS","NOBLE","RICHY","VNG","HYDRO","LALIN",
   "PRINC","BR","PRIME","SCI","MJD","CI","PRIN","NC","CHEWA","TTCL",
   "CHO","TNL","KEX"
};

// Excluded (อยู่ใน DOM_High, DOM_Delta, DOM_Stocks_A แล้ว)
string EXCLUDED[] = {
   "DELTA",
   "GULF","BDMS","HANA","BANPU","PTTEP","IVL","AOT","KTB","KCE",
   "TTB","MINT","SCGP","IRPC","SCC","WHA","TFG","BH","TRUE",
   "CPALL","ADVANC","PTTGC",
   // SET50 (อยู่ใน DOM_Stocks_A แล้ว)
   "PTT","OR","SCB","KBANK","BBL","CPN","CPF","HMPRO","LH","BEM",
   "EA","TISCO","SAWAD","TIDLOR","GPSC","CRC","BCH","MTC","BTS","AWC",
   "BGRIM","EGCO","RATCH","KKP","BAY","TOP","TCAP","BJC","VGI","KTC",
   "AEONTS","BCP"
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
   Print("[STOCKS_B] Started | ", ok, " symbols | flush=", FLUSH_MS, "ms | file=", OUT_FILE);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < g_sub_count; i++) MarketBookRelease(g_subs[i]);
   if(g_fh != INVALID_HANDLE)
     { FileFlush(g_fh); FileClose(g_fh); g_fh = INVALID_HANDLE; }\
   Print("[STOCKS_B] Stopped. events=", g_events);
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
                IntegerToString((long)book[i].volume),
                DoubleToString(book[i].volume_dbl, 2));
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
         FileWrite(g_fh, TimestampUs(), "STOCKS_B", "HEARTBEAT", "", "", "");
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
        { Print("[STOCKS_B] ERROR opening file: ", GetLastError()); return false; }
      FileWrite(g_fh, "timestamp_us","symbol","type","price","volume","volume_dbl");
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
