//+------------------------------------------------------------------+
//| MTChartBridgeEA.mq5                                              |
//| Phase 2: local command intake and response outbox.                |
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
const string INBOX_FOLDER       = "MTChartBridge\\inbox";
const string OUTBOX_FOLDER      = "MTChartBridge\\outbox";
const string PROCESSED_FOLDER   = "MTChartBridge\\processed";
const string FAILED_FOLDER      = "MTChartBridge\\failed";
const string COMMON_FOLDER_HINT = "Terminal/Common/Files/MTChartBridge";
const string EA_PHASE           = "phase-2-command-intake";

int      g_polling_interval_ms = 250;
ulong    g_heartbeat_counter   = 0;
datetime g_last_error_log_time = 0;
string   g_processed_command_ids[];

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

void JsonSkipWhitespace(const string json, int &position)
{
   const int length = StringLen(json);
   while(position < length)
   {
      const ushort ch = StringGetCharacter(json, position);
      if(ch != 32 && ch != 9 && ch != 10 && ch != 13)
         return;

      position++;
   }
}

bool JsonFindValueStart(const string json, const string key, int &position)
{
   const string needle = "\"" + key + "\"";
   const int key_position = StringFind(json, needle);
   if(key_position < 0)
      return false;

   const int colon_position = StringFind(json, ":", key_position + StringLen(needle));
   if(colon_position < 0)
      return false;

   position = colon_position + 1;
   JsonSkipWhitespace(json, position);
   return position < StringLen(json);
}

bool JsonExtractString(const string json, const string key, string &value)
{
   int position = 0;
   if(!JsonFindValueStart(json, key, position))
      return false;

   const int length = StringLen(json);
   if(StringGetCharacter(json, position) != 34)
      return false;

   position++;
   string result = "";
   bool escaping = false;

   while(position < length)
   {
      const ushort ch = StringGetCharacter(json, position);

      if(escaping)
      {
         if(ch == 34)
            result += "\"";
         else if(ch == 92)
            result += "\\";
         else if(ch == 47)
            result += "/";
         else if(ch == 98)
            result += " ";
         else if(ch == 102)
            result += " ";
         else if(ch == 110)
            result += "\n";
         else if(ch == 114)
            result += "\r";
         else if(ch == 116)
            result += "\t";
         else
            result += ShortToString(ch);

         escaping = false;
      }
      else if(ch == 92)
      {
         escaping = true;
      }
      else if(ch == 34)
      {
         value = result;
         return true;
      }
      else
      {
         result += ShortToString(ch);
      }

      position++;
   }

   return false;
}

bool JsonExtractBool(const string json, const string key, bool &value)
{
   int position = 0;
   if(!JsonFindValueStart(json, key, position))
      return false;

   if(StringSubstr(json, position, 4) == "true")
   {
      value = true;
      return true;
   }

   if(StringSubstr(json, position, 5) == "false")
   {
      value = false;
      return true;
   }

   return false;
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

bool ReadCommonTextFile(const string file_path, string &content)
{
   content = "";
   ResetLastError();

   const int handle = FileOpen(file_path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      LogLastError("FileOpen(" + file_path + ")");
      return false;
   }

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(content != "")
         content += "\n";
      content += line;
   }

   FileClose(handle);
   return true;
}

bool CopyThenDeleteCommonFile(const string source_path, const string destination_path)
{
   ResetLastError();
   if(!FileIsExist(source_path, FILE_COMMON))
   {
      LogDebug("Archive skipped because file does not exist: " + source_path);
      return true;
   }

   if(FileIsExist(destination_path, FILE_COMMON))
   {
      if(!FileDelete(destination_path, FILE_COMMON))
      {
         LogLastError("FileDelete(" + destination_path + ")");
         return false;
      }
   }

   ResetLastError();
   if(!FileCopy(source_path, FILE_COMMON, destination_path, FILE_REWRITE | FILE_COMMON))
   {
      LogLastError("FileCopy(" + source_path + " -> " + destination_path + ")");
      return false;
   }

   ResetLastError();
   if(!FileDelete(source_path, FILE_COMMON))
   {
      LogLastError("FileDelete(" + source_path + ")");
      return false;
   }

   return true;
}

bool ArchiveCommandFiles(const string command_id, const string destination_folder)
{
   const string payload_name = command_id + ".command.json.tmp";
   const string marker_name = command_id + ".command.ready";
   const string payload_source = INBOX_FOLDER + "\\" + payload_name;
   const string marker_source = INBOX_FOLDER + "\\" + marker_name;
   const string payload_destination = destination_folder + "\\" + payload_name;
   const string marker_destination = destination_folder + "\\" + marker_name;

   bool archived = true;
   if(!CopyThenDeleteCommonFile(payload_source, payload_destination))
      archived = false;
   if(!CopyThenDeleteCommonFile(marker_source, marker_destination))
      archived = false;

   if(archived)
      LogInfo("Command moved to " + destination_folder + ": " + command_id);

   return archived;
}

bool WriteResponseFiles(const string command_id, const string response_json)
{
   const string response_path = OUTBOX_FOLDER + "\\" + command_id + ".response.json.tmp";
   const string ready_path = OUTBOX_FOLDER + "\\" + command_id + ".response.ready";

   if(FileIsExist(ready_path, FILE_COMMON))
   {
      if(!FileDelete(ready_path, FILE_COMMON))
      {
         LogLastError("FileDelete(" + ready_path + ")");
         return false;
      }
   }

   if(!WriteCommonTextFile(response_path, response_json))
      return false;

   if(!WriteCommonTextFile(ready_path, ""))
      return false;

   LogInfo("Response written: " + response_path + " and " + ready_path);
   return true;
}

string BuildAcceptedResponseJson(const string command_id,
                                 const string symbol,
                                 const string side,
                                 const bool dry_run)
{
   string json = "{\n";
   json += "  \"type\": \"trade.response\",\n";
   json += "  \"id\": " + JsonString(command_id) + ",\n";
   json += "  \"status\": \"accepted\",\n";
   json += "  \"code\": \"COMMAND_RECEIVED\",\n";
   json += "  \"message\": \"Command received by EA. No trade was executed in Phase 2.\",\n";
   json += "  \"ea_phase\": " + JsonString(EA_PHASE) + ",\n";
   json += "  \"symbol\": " + JsonString(symbol) + ",\n";
   json += "  \"side\": " + JsonString(side) + ",\n";
   json += "  \"dry_run\": " + (dry_run ? "true" : "false") + ",\n";
   json += "  \"timestamp_local\": " + JsonString(LocalTimestamp()) + "\n";
   json += "}\n";
   return json;
}

string BuildRejectedResponseJson(const string command_id, const string message)
{
   string json = "{\n";
   json += "  \"type\": \"trade.response\",\n";
   json += "  \"id\": " + JsonString(command_id) + ",\n";
   json += "  \"status\": \"rejected\",\n";
   json += "  \"code\": \"INVALID_COMMAND\",\n";
   json += "  \"message\": " + JsonString(message) + ",\n";
   json += "  \"ea_phase\": " + JsonString(EA_PHASE) + ",\n";
   json += "  \"timestamp_local\": " + JsonString(LocalTimestamp()) + "\n";
   json += "}\n";
   return json;
}

bool IsCommandRemembered(const string command_id)
{
   for(int i = 0; i < ArraySize(g_processed_command_ids); i++)
   {
      if(g_processed_command_ids[i] == command_id)
         return true;
   }

   return false;
}

void RememberCommandId(const string command_id)
{
   if(IsCommandRemembered(command_id))
      return;

   const int current_size = ArraySize(g_processed_command_ids);
   const int max_cached = 128;

   if(current_size < max_cached)
   {
      ArrayResize(g_processed_command_ids, current_size + 1);
      g_processed_command_ids[current_size] = command_id;
      return;
   }

   for(int i = 1; i < max_cached; i++)
      g_processed_command_ids[i - 1] = g_processed_command_ids[i];

   g_processed_command_ids[max_cached - 1] = command_id;
}

bool ReadyFileToCommandId(const string ready_file_name, string &command_id)
{
   const string suffix = ".command.ready";
   const int suffix_length = StringLen(suffix);
   const int name_length = StringLen(ready_file_name);

   if(name_length <= suffix_length)
      return false;

   if(StringSubstr(ready_file_name, name_length - suffix_length, suffix_length) != suffix)
      return false;

   command_id = StringSubstr(ready_file_name, 0, name_length - suffix_length);
   return command_id != "";
}

void RejectCommand(const string command_id, const string message)
{
   LogInfo("Rejecting command " + command_id + ": " + message);

   if(WriteResponseFiles(command_id, BuildRejectedResponseJson(command_id, message)))
      RememberCommandId(command_id);
   else
      LogInfo("Could not write rejected response for command: " + command_id);

   ArchiveCommandFiles(command_id, FAILED_FOLDER);
}

void ProcessReadyCommand(const string ready_file_name)
{
   string command_id = "";
   if(!ReadyFileToCommandId(ready_file_name, command_id))
   {
      LogInfo("Invalid ready filename detected: " + ready_file_name);
      return;
   }

   if(IsCommandRemembered(command_id))
   {
      LogDebug("Command already processed in this EA session: " + command_id);
      return;
   }

   LogInfo("Command ready file detected: " + INBOX_FOLDER + "\\" + ready_file_name);

   const string command_path = INBOX_FOLDER + "\\" + command_id + ".command.json.tmp";
   string command_json = "";
   if(!ReadCommonTextFile(command_path, command_json))
   {
      RejectCommand(command_id, "Command payload is missing or unreadable.");
      return;
   }

   LogInfo("Command file read: " + command_path);

   string type = "";
   string id = "";
   string symbol = "";
   string side = "";
   bool dry_run = false;

   if(!JsonExtractString(command_json, "type", type))
   {
      RejectCommand(command_id, "Command is missing string field: type.");
      return;
   }

   if(!JsonExtractString(command_json, "id", id))
   {
      RejectCommand(command_id, "Command is missing string field: id.");
      return;
   }

   if(!JsonExtractString(command_json, "symbol", symbol))
   {
      RejectCommand(command_id, "Command is missing string field: symbol.");
      return;
   }

   if(!JsonExtractString(command_json, "side", side))
   {
      RejectCommand(command_id, "Command is missing string field: side.");
      return;
   }

   if(!JsonExtractBool(command_json, "dry_run", dry_run))
   {
      RejectCommand(command_id, "Command is missing boolean field: dry_run.");
      return;
   }

   if(type != "trade.open")
   {
      RejectCommand(command_id, "Command type must be trade.open.");
      return;
   }

   if(id == "")
   {
      RejectCommand(command_id, "Command id must not be empty.");
      return;
   }

   if(id != command_id)
   {
      RejectCommand(command_id, "Command id does not match ready filename.");
      return;
   }

   if(symbol == "")
   {
      RejectCommand(command_id, "Command symbol must not be empty.");
      return;
   }

   if(side == "")
   {
      RejectCommand(command_id, "Command side must not be empty.");
      return;
   }

   if(!WriteResponseFiles(command_id, BuildAcceptedResponseJson(command_id, symbol, side, dry_run)))
   {
      LogInfo("Could not write accepted response for command: " + command_id);
      return;
   }

   RememberCommandId(command_id);
   ArchiveCommandFiles(command_id, PROCESSED_FOLDER);
}

bool ProcessOneReadyCommand()
{
   string ready_file_name = "";
   const long find_handle = FileFindFirst(INBOX_FOLDER + "\\*.command.ready", ready_file_name, FILE_COMMON);
   if(find_handle == INVALID_HANDLE)
   {
      ResetLastError();
      return false;
   }

   bool found_unprocessed = false;

   do
   {
      string command_id = "";
      if(!ReadyFileToCommandId(ready_file_name, command_id))
         continue;

      if(IsCommandRemembered(command_id))
         continue;

      ProcessReadyCommand(ready_file_name);
      found_unprocessed = true;
      break;
   }
   while(FileFindNext(find_handle, ready_file_name));

   FileFindClose(find_handle);
   return found_unprocessed;
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

   LogInfo("Initializing MTChartBridgeEA phase 2.");
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

   if(!WriteStatusFile())
      LogLastErrorThrottled("WriteStatusFile");

   // Phase 2 reads at most one local command per timer tick and never trades.
   ProcessOneReadyCommand();
}
