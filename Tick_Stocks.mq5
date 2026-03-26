//+------------------------------------------------------------------+
//| Tick_Stocks.mq5                                                  |
//| Tick Collector — หุ้นทั้งหมด (~157 ตัว)                        |
//| v1: CopyTicksRange poll 100ms | Output: tick_stocks.csv          |
//+------------------------------------------------------------------+
#property copyright "Quant"
#property version   "1.00"
#property strict
#property description "Tick Collector — All stocks (HIGH + DELTA + SET50 + Rest) | poll 100ms"

//── Config ─────────────────────────────────────────────────────────
#define TICK_FILE       "tick\\tick_stocks.csv"
#define POLL_MS         100    // poll ทุก 100ms — tick งานเบา ใช้ EA เดียวได้
#define HEARTBEAT_SEC   30

//── ALL stocks: HIGH(21) + DELTA(1) + SET50_A(32) + REST_B(103) ──
string ALL_STOCKS[] = {
   // ── HIGH stocks (DOM_High.mq5) ──
   "GULF","BDMS","HANA","BANPU","PTTEP","IVL","AOT","KTB","KCE",
   "TTB","MINT","SCGP","IRPC","SCC","WHA","TFG","BH","TRUE",
   "CPALL","ADVANC","PTTGC",
   // ── DELTA (DOM_Delta.mq5) ──
   "DELTA",
   // ── SET50 / DOM_Stocks_A ──
   "PTT","OR","SCB","KBANK","BBL","CPN","CPF","HMPRO","LH","BEM",
   "EA","TISCO","SAWAD","TIDLOR","GPSC","CRC","BCH","MTC","BTS","AWC",
   "BGRIM","EGCO","RATCH","KKP","BAY","TOP","TCAP","BJC","VGI","KTC",
   "AEONTS","BCP",
   // ── Non-SET50 / DOM_Stocks_B ──
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

//── Globals ─────────────────────────────────────────────────────────
int      g_fh          = INVALID_HANDLE;
long     g_ticks       = 0;
datetime g_last_hb     = 0;

// last tick time_msc per symbol (parallel array to ALL_STOCKS)
ulong    g_last_ms[];
int      g_sym_count   = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!OpenFile()) return INIT_FAILED;

   int n = ArraySize(ALL_STOCKS);
   ArrayResize(g_last_ms, n);
   ulong now_ms = (ulong)TimeCurrent() * 1000;

   int ok = 0;
   for(int i = 0; i < n; i++)
     {
      g_last_ms[i] = now_ms;   // เริ่มเก็บจาก "ตอนนี้"
      if(SymbolSelect(ALL_STOCKS[i], true)) { ok++; g_sym_count++; }
     }

   g_last_hb = TimeCurrent();
   EventSetMillisecondTimer(POLL_MS);
   Print("[TICK_STOCKS] Started | ", ok, "/", n, " symbols | poll=", POLL_MS,
         "ms | file=", TICK_FILE);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_fh != INVALID_HANDLE)
     { FileFlush(g_fh); FileClose(g_fh); g_fh = INVALID_HANDLE; }
   Print("[TICK_STOCKS] Stopped. ticks=", g_ticks);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();
   int n = ArraySize(ALL_STOCKS);

   // ─ Poll all symbols ─
   for(int i = 0; i < n; i++)
     {
      MqlTick ticks[];
      // COPY_TICKS_TRADE = เฉพาะ tick ที่มี last price (deal จริง)
      int cnt = CopyTicksRange(ALL_STOCKS[i], ticks, COPY_TICKS_TRADE,
                               g_last_ms[i], 0);
      if(cnt <= 0) continue;

      for(int k = 0; k < cnt; k++)
        {
         if(ticks[k].last == 0.0) continue;
         WriteTick(ALL_STOCKS[i], ticks[k]);
        }
      g_last_ms[i] = ticks[cnt-1].time_msc + 1;
     }

   // ─ Flush ─
   if(g_fh != INVALID_HANDLE) FileFlush(g_fh);

   // ─ Heartbeat ─
   if(now - g_last_hb >= HEARTBEAT_SEC)
     {
      if(g_fh != INVALID_HANDLE)
         FileWrite(g_fh, FormatMs((ulong)now * 1000), "STOCKS",
                   "HEARTBEAT", "", "", "", "", "");
      g_last_hb = now;
     }
  }

void OnTick() { }

//+------------------------------------------------------------------+
void WriteTick(const string &sym, const MqlTick &t)
  {
   if(g_fh == INVALID_HANDLE && !OpenFile()) return;
   string side = "";
   if((t.flags & TICK_FLAG_BUY)  != 0) side = "buy";
   if((t.flags & TICK_FLAG_SELL) != 0) side = "sell";
   FileWrite(g_fh,
             FormatMs(t.time_msc),
             sym,
             DoubleToString(t.last,        2),
             IntegerToString(t.volume),
             DoubleToString(t.volume_real, 4),
             side,
             DoubleToString(t.bid, 2),
             DoubleToString(t.ask, 2));
   g_ticks++;
  }

string FormatMs(ulong time_msc)
  {
   datetime sec = (datetime)(time_msc / 1000);
   int      ms  = (int)(time_msc % 1000);
   MqlDateTime dt; TimeToStruct(sec, dt);
   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d.%03d000",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, ms);
  }

bool OpenFile()
  {
   if(g_fh != INVALID_HANDLE) { FileClose(g_fh); g_fh = INVALID_HANDLE; }
   g_fh = FileOpen(TICK_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
   if(g_fh == INVALID_HANDLE)
     {
      g_fh = FileOpen(TICK_FILE, FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
      if(g_fh == INVALID_HANDLE)
        { Print("[TICK_STOCKS] ERROR opening file: ", GetLastError()); return false; }
      FileWrite(g_fh, "timestamp_ms","symbol","last","volume","volume_real","side","bid","ask");
      FileFlush(g_fh); return true;
     }
   FileSeek(g_fh, 0, SEEK_END); return true;
  }
//+------------------------------------------------------------------+
