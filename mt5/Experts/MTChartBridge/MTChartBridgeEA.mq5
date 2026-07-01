//+------------------------------------------------------------------+
//| MTChartBridgeEA.mq5                                              |
//| Phase 1: local shared-folder transport foundation only.           |
//+------------------------------------------------------------------+
#property copyright "MTChartBridge"
#property link      ""
#property version   "1.000"
#property strict

input int    PollingIntervalMs = 250;
input bool   EnableDebugLogs   = true;
input string ProductName       = "MTChartBridge";
input int    MagicNumber       = 20260701;

#define MTCB_VERSION "0.1.0"

const string ROOT_FOLDER        = "MTChartBridge";
const string MARKER_FILE_PATH   = "MTChartBridge\\.mtchartbridge-folder";
const string STATUS_FILE_PATH   = "MTChartBridge\\status.json";
const string COMMON_FOLDER_HINT = "Terminal/Common/Files/MTChartBridge";

int      g_polling_interval_ms = 250;
ulong    g_heartbeat_counter   = 0;
datetime g_last_error_log_time = 0;

bool CommonFolderAcceptsFile(const string folder_path, int &probe_error);

//+------------------------------------------------------------------+
//| Logging helpers.                                                  |
//+------------------------------------------------------------------+
void LogInfo(const string message)
{
   PrintFormat("[%s] %s", ProductName, message);
}

void LogDebug(const string message)
{
   if(EnableDebugLogs)
      PrintFormat("[%s][debug] %s", ProductName, message);
}

void LogLastError(const string action)
{
   const int error_code = GetLastError();
   PrintFormat("[%s][error] %s failed. GetLastError=%d", ProductName, action, error_code);
   ResetLastError();
}

void LogLastErrorThrottled(const string action)
{
   const datetime now = TimeLocal();
   if(now - g_last_error_log_time >= 5)
   {
      g_last_error_log_time = now;
      LogLastError(action);
   }
   else
   {
      ResetLastError();
   }
}

//+------------------------------------------------------------------+
//| JSON helpers.                                                     |
//+------------------------------------------------------------------+
string JsonEscape(const string value)
{
   string escaped = "";
   const int length = StringLen(value);

   for(int i = 0; i < length; i++)
   {
      const ushort ch = StringGetCharacter(value, i);

      if(ch == 92)
         escaped += "\\\\";
      else if(ch == 34)
         escaped += "\\\"";
      else if(ch == 10)
         escaped += "\\n";
      else if(ch == 13)
         escaped += "\\r";
      else if(ch == 9)
         escaped += "\\t";
      else if(ch < 32)
         escaped += " ";
      else
         escaped += ShortToString(ch);
   }

   return escaped;
}

string JsonString(const string value)
{
   return "\"" + JsonEscape(value) + "\"";
}

string LocalTimestamp()
{
   return TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
}

//+------------------------------------------------------------------+
//| Common-files folder and file operations.                          |
//+------------------------------------------------------------------+
bool EnsureCommonFolder(const string folder_path)
{
   ResetLastError();

   if(FolderCreate(folder_path, FILE_COMMON))
   {
      LogInfo("Created common folder: " + folder_path);
      return true;
   }

   const int create_error = GetLastError();
   int probe_error = 0;

   // FolderCreate returns false when the folder already exists. A short-lived
   // probe file verifies that the folder is available without relying on a
   // separate folder-existence API.
   if(CommonFolderAcceptsFile(folder_path, probe_error))
   {
      LogDebug("Folder available: " + folder_path);
      return true;
   }

   PrintFormat("[%s][error] FolderCreate(%s) failed. create_error=%d probe_error=%d",
               ProductName,
               folder_path,
               create_error,
               probe_error);
   ResetLastError();
   return false;
}

bool CommonFolderAcceptsFile(const string folder_path, int &probe_error)
{
   const string probe_path = folder_path + "\\.mtchartbridge-probe.tmp";

   ResetLastError();
   const int handle = FileOpen(probe_path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      probe_error = GetLastError();
      ResetLastError();
      return false;
   }

   FileClose(handle);

   ResetLastError();
   if(FileIsExist(probe_path, FILE_COMMON))
      FileDelete(probe_path, FILE_COMMON);

   probe_error = 0;
   ResetLastError();
   return true;
}

bool EnsureFolderStructure()
{
   if(!EnsureCommonFolder(ROOT_FOLDER))
      return false;

   string folders[] =
   {
      "inbox",
      "processing",
      "outbox",
      "processed",
      "failed",
      "logs"
   };

   for(int i = 0; i < ArraySize(folders); i++)
   {
      if(!EnsureCommonFolder(ROOT_FOLDER + "\\" + folders[i]))
         return false;
   }

   return true;
}

bool WriteCommonTextFile(const string file_path, const string content)
{
   ResetLastError();

   if(FileIsExist(file_path, FILE_COMMON))
   {
      if(!FileDelete(file_path, FILE_COMMON))
      {
         LogLastError("FileDelete(" + file_path + ")");
         return false;
      }
   }

   ResetLastError();
   const int handle = FileOpen(file_path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      LogLastError("FileOpen(" + file_path + ")");
      return false;
   }

   const uint written = FileWriteString(handle, content);
   if(written == 0 && StringLen(content) > 0)
   {
      FileClose(handle);
      LogLastError("FileWriteString(" + file_path + ")");
      return false;
   }

   FileFlush(handle);
   FileClose(handle);
   return true;
}

string BuildMarkerJson()
{
   string json = "{\n";
   json += "  \"type\": \"mtchartbridge.folder\",\n";
   json += "  \"product\": " + JsonString(ProductName) + ",\n";
   json += "  \"version\": " + JsonString(MTCB_VERSION) + ",\n";
   json += "  \"note\": \"This folder is used by MTChartBridge EA and Chrome Extension to exchange local command and response files.\"\n";
   json += "}\n";
   return json;
}

bool WriteMarkerFile()
{
   if(!WriteCommonTextFile(MARKER_FILE_PATH, BuildMarkerJson()))
      return false;

   LogInfo("Updated marker file: " + MARKER_FILE_PATH);
   return true;
}

string BuildStatusJson()
{
   string json = "{\n";
   json += "  \"type\": \"mtchartbridge.status\",\n";
   json += "  \"product\": " + JsonString(ProductName) + ",\n";
   json += "  \"version\": " + JsonString(MTCB_VERSION) + ",\n";
   json += "  \"ea_state\": \"running\",\n";
   json += "  \"account_login\": " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ",\n";
   json += "  \"account_server\": " + JsonString(AccountInfoString(ACCOUNT_SERVER)) + ",\n";
   json += "  \"account_company\": " + JsonString(AccountInfoString(ACCOUNT_COMPANY)) + ",\n";
   json += "  \"account_currency\": " + JsonString(AccountInfoString(ACCOUNT_CURRENCY)) + ",\n";
   json += "  \"account_trade_mode\": " + IntegerToString(AccountInfoInteger(ACCOUNT_TRADE_MODE)) + ",\n";
   json += "  \"terminal_build\": " + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)) + ",\n";
   json += "  \"chart_symbol\": " + JsonString(_Symbol) + ",\n";
   json += "  \"chart_period\": " + JsonString(EnumToString((ENUM_TIMEFRAMES)_Period)) + ",\n";
   json += "  \"magic_number\": " + IntegerToString(MagicNumber) + ",\n";
   json += "  \"polling_interval_ms\": " + IntegerToString(g_polling_interval_ms) + ",\n";
   json += "  \"timestamp_local\": " + JsonString(LocalTimestamp()) + ",\n";
   json += "  \"heartbeat_counter\": " + IntegerToString((long)g_heartbeat_counter) + "\n";
   json += "}\n";
   return json;
}

bool WriteStatusFile()
{
   return WriteCommonTextFile(STATUS_FILE_PATH, BuildStatusJson());
}

//+------------------------------------------------------------------+
//| Expert lifecycle.                                                 |
//+------------------------------------------------------------------+
int OnInit()
{
   g_polling_interval_ms = PollingIntervalMs;
   if(g_polling_interval_ms < 10)
   {
      LogInfo("PollingIntervalMs was below 10 ms; using 10 ms instead.");
      g_polling_interval_ms = 10;
   }

   LogInfo("Initializing MTChartBridgeEA phase 1.");
   LogInfo("Common folder for Chrome Extension access later: " + COMMON_FOLDER_HINT);

   if(!EnsureFolderStructure())
   {
      LogInfo("Initialization stopped because the common folder structure could not be created.");
      return INIT_FAILED;
   }

   if(!WriteMarkerFile())
   {
      LogInfo("Initialization stopped because the marker file could not be written.");
      return INIT_FAILED;
   }

   g_heartbeat_counter = 0;
   if(!WriteStatusFile())
   {
      LogInfo("Initialization stopped because status.json could not be written.");
      return INIT_FAILED;
   }

   ResetLastError();
   if(!EventSetMillisecondTimer(g_polling_interval_ms))
   {
      LogLastError("EventSetMillisecondTimer");
      return INIT_FAILED;
   }

   LogInfo("Initialized successfully. Timer interval: " + IntegerToString(g_polling_interval_ms) + " ms.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   LogInfo("Deinitialized MTChartBridgeEA. Reason code: " + IntegerToString(reason));
}

void OnTimer()
{
   g_heartbeat_counter++;

   // Phase 1 keeps the timer intentionally small: only a heartbeat status
   // update is written. No inbox processing or trading is performed here.
   if(!WriteStatusFile())
      LogLastErrorThrottled("WriteStatusFile");
}
