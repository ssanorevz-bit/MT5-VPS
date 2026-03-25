//+------------------------------------------------------------------+
//| DOM_Collector.mq5                                                |
//| เก็บ DOM 10 levels สำหรับ S50IF_CON + S50 Options ทุก Strike   |
//|                                                                  |
//| วิธีติดตั้ง:                                                     |
//|   1. วางไฟล์นี้ใน:                                              |
//|      %APPDATA%\MetaQuotes\Terminal\<ID>\MQL5\Experts\            |
//|   2. กด Compile (F7) ใน MetaEditor                              |
//|   3. ลาก EA ไปวางบน chart S50IF ใดก็ได้                        |
//|   4. เปิด "Allow DLL imports" ไม่จำเป็น                        |
//|   5. EA จะสร้างไฟล์ dom_live.csv ใน:                           |
//|      %APPDATA%\MetaQuotes\Terminal\<ID>\MQL5\Files\              |
//+------------------------------------------------------------------+
#property copyright "Quant"
#property version   "2.00"
#property strict
#property description "DOM Collector — 10 levels for S50IF + S50 Options"

//── Input Parameters ──────────────────────────────────────────────
input string   OutFileName     = "dom_live.csv";   // ชื่อไฟล์ output
input bool     CollectOptions  = true;             // เก็บ S50 Options ด้วย
input bool     CollectFutures  = true;             // เก็บ S50IF_CON
input bool     LogToJournal    = true;             // แสดง log ใน Experts tab

//── Globals ───────────────────────────────────────────────────────
int      g_fh        = INVALID_HANDLE;
string   g_symbols[];
int      g_sym_count = 0;
datetime g_last_discover = 0;

//+------------------------------------------------------------------+
//| EA Init                                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   // เปิดไฟล์ CSV (สร้างใหม่ทุกครั้งที่ EA เริ่ม)
   g_fh = FileOpen(OutFileName,
                   FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI,
                   ',');
   if(g_fh == INVALID_HANDLE)
     {
      Print("[DOM_Collector] ERROR: ไม่สามารถเปิดไฟล์ได้ code=", GetLastError());
      return INIT_FAILED;
     }

   // เขียน header
   FileWrite(g_fh, "timestamp_ms", "symbol", "type", "price", "volume");
   FileFlush(g_fh);

   // Discover symbols + subscribe
   DiscoverAndSubscribe();

   if(LogToJournal)
      Print("[DOM_Collector] Started — ", g_sym_count, " symbols | file=", OutFileName);

   // Refresh symbols ทุก 30 นาที (detect options series ใหม่)
   EventSetTimer(1800);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| EA Deinit                                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   // Unsubscribe DOM
   for(int i = 0; i < g_sym_count; i++)
      MarketBookRelease(g_symbols[i]);

   // ปิดไฟล์
   if(g_fh != INVALID_HANDLE)
     {
      FileClose(g_fh);
      g_fh = INVALID_HANDLE;
     }

   if(LogToJournal)
      Print("[DOM_Collector] Stopped.");
  }

//+------------------------------------------------------------------+
//| DOM Event — เรียกทุกครั้งที่ Order Book เปลี่ยน                 |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
  {
   // ตรวจว่า symbol นี้เราสนใจ
   if(!IsTracked(symbol))
      return;

   // ดึง Order Book (MQL5 → ได้สูงสุด 20 levels จาก TFEX)
   MqlBookInfo book[];
   if(!MarketBookGet(symbol, book))
      return;

   int count = ArraySize(book);
   if(count <= 0)
      return;

   // timestamp แบบ millisecond
   string ts = TimestampMs();

   // เขียนทุก level ลงไฟล์
   if(g_fh == INVALID_HANDLE)
      return;

   for(int i = 0; i < count; i++)
     {
      string t = BookTypeStr(book[i].type);
      if(t == "")
         continue;  // ข้าม unknown type

      FileWrite(g_fh,
                ts,
                symbol,
                t,
                DoubleToString(book[i].price, 2),
                IntegerToString((long)book[i].volume));
     }
   FileFlush(g_fh);
  }

//+------------------------------------------------------------------+
//| Timer — re-discover options series ใหม่ทุก 30 นาที             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   DiscoverAndSubscribe();
  }

//+------------------------------------------------------------------+
//| ค้นหา S50 symbols + subscribe DOM                               |
//+------------------------------------------------------------------+
void DiscoverAndSubscribe()
  {
   string new_syms[];
   int    new_count = 0;

   // S50IF_CON
   if(CollectFutures)
      AddUnique(new_syms, new_count, "S50IF_CON");

   // S50 Options — scan ทุก symbol ใน MT5
   if(CollectOptions)
     {
      int total = SymbolsTotal(false);
      for(int i = 0; i < total; i++)
        {
         string name = SymbolName(i, false);
         if(IsS50Option(name))
            AddUnique(new_syms, new_count, name);
        }
     }

   // Subscribe เฉพาะ symbols ใหม่ที่ยังไม่ได้ subscribe
   int added = 0;
   for(int i = 0; i < new_count; i++)
     {
      if(!IsTracked(new_syms[i]))
        {
         if(MarketBookAdd(new_syms[i]))
           {
            AddUnique(g_symbols, g_sym_count, new_syms[i]);
            added++;
           }
        }
     }

   if(added > 0 && LogToJournal)
      Print("[DOM_Collector] +", added, " symbols subscribed. Total=", g_sym_count);
  }

//+------------------------------------------------------------------+
//| ตรวจว่าชื่อ symbol เป็น S50 Option หรือเปล่า                   |
//| Pattern: S50[H|J|K|M|N|Q|U|V|X|Z][yy][C|P][strike]             |
//| ตัวอย่าง: S50H26C950, S50M26P800                                |
//+------------------------------------------------------------------+
bool IsS50Option(const string &name)
  {
   if(StringLen(name) < 9)
      return false;
   if(StringSubstr(name, 0, 3) != "S50")
      return false;

   // ตัวที่ 3 = expiry month code
   string month_codes = "HJKMNQUVXZ";
   string m = StringSubstr(name, 3, 1);
   if(StringFind(month_codes, m) < 0)
      return false;

   // ต้องมี C หรือ P ตั้งแต่ตำแหน่ง 5 ขึ้นไป
   if(StringFind(name, "C", 5) < 0 && StringFind(name, "P", 5) < 0)
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| ตรวจว่า symbol อยู่ใน tracked list ไหม                         |
//+------------------------------------------------------------------+
bool IsTracked(const string &sym)
  {
   for(int i = 0; i < g_sym_count; i++)
      if(g_symbols[i] == sym)
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| เพิ่ม symbol ลง array โดยไม่ซ้ำ                                |
//+------------------------------------------------------------------+
void AddUnique(string &arr[], int &count, const string &sym)
  {
   for(int i = 0; i < count; i++)
      if(arr[i] == sym)
         return;
   ArrayResize(arr, count + 1);
   arr[count] = sym;
   count++;
  }

//+------------------------------------------------------------------+
//| แปลง BOOK_TYPE → string                                         |
//+------------------------------------------------------------------+
string BookTypeStr(const ENUM_BOOK_TYPE t)
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
//| สร้าง timestamp แบบ millisecond (UTC)                           |
//| Format: 2026-03-25 11:24:20.450                                  |
//+------------------------------------------------------------------+
string TimestampMs()
  {
   MqlDateTime dt;
   datetime    sec  = TimeCurrent(dt);
   uint        ms   = GetTickCount() % 1000;

   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d.%03d",
                       dt.year, dt.mon, dt.day,
                       dt.hour, dt.min, dt.sec,
                       ms);
  }

//+------------------------------------------------------------------+
//| OnTick — ไม่ได้ใช้ แต่ต้องมีเพื่อให้ EA compile ได้           |
//+------------------------------------------------------------------+
void OnTick() { }
//+------------------------------------------------------------------+
