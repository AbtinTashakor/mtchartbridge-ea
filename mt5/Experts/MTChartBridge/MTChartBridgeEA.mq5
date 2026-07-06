//+------------------------------------------------------------------+
//| MTChartBridgeEA.mq5                                              |
//| Phase 8: persistent idempotency + execution audit log.            |
//+------------------------------------------------------------------+
#property copyright "MTChartBridge"
#property link      ""
#property version   "1.000"
#property strict

input int    PollingIntervalMs = 250;
input bool   EnableDebugLogs   = true;
input string ProductName       = "MTChartBridge";
input int    MagicNumber       = 20260701;
input bool   EnforceCommandTtl = true;
input int    MaxCommandTtlMs   = 30000;
input int    ProcessedCommandCacheSize = 200;
input int    RejectIfSpreadAbovePoints = 0;
input string AllowedSymbols = "";
input double MaxRiskPercent = 2.0;
input double MaxVolume = 0.0;
input bool   EnableOrderCheck = true;
input int    MaxDeviationPoints = 20;
input bool   EnableLiveTrading = false;
input bool   AllowLiveOrderSend = false;
input string LiveTradingAcknowledgement = "";
input bool   EnablePersistentIdempotency = true;
input bool   EnableAuditLog = true;

#define MTCB_VERSION "0.1.0"

const string ROOT_FOLDER        = "MTChartBridge";
const string MARKER_FILE_PATH   = "MTChartBridge\\.mtchartbridge-folder";
const string STATUS_FILE_PATH   = "MTChartBridge\\status.json";
const string INBOX_FOLDER       = "MTChartBridge\\inbox";
const string OUTBOX_FOLDER      = "MTChartBridge\\outbox";
const string PROCESSED_FOLDER   = "MTChartBridge\\processed";
const string FAILED_FOLDER      = "MTChartBridge\\failed";
const string STATE_FOLDER       = "MTChartBridge\\state";
const string COMMAND_STATE_FOLDER = "MTChartBridge\\state\\commands";
const string AUDIT_FOLDER       = "MTChartBridge\\audit";
const string AUDIT_EVENTS_PATH  = "MTChartBridge\\audit\\events.jsonl";
const string COMMON_FOLDER_HINT = "Terminal/Common/Files/MTChartBridge";
const string EA_PHASE           = "phase-8-persistent-idempotency";
const string LIVE_TRADING_ACKNOWLEDGEMENT = "I_UNDERSTAND_THIS_CAN_OPEN_REAL_TRADES";

int      g_polling_interval_ms = 250;
int      g_processed_command_cache_size = 200;
ulong    g_heartbeat_counter   = 0;
datetime g_last_error_log_time = 0;

struct ProcessedCommandCacheEntry
{
   string id;
   string status;
   string code;
};

struct CommandData
{
   string type;
   string id;
   string created_at;
   int    ttl_ms;
   string symbol;
   string side;
   double risk_percent;
   double stop_loss;
   double take_profit;
   bool   dry_run;
   string comment;
   string client_version;
   string source;
   bool   has_take_profit;
   bool   has_comment;
   bool   has_client_version;
   bool   has_source;
   bool   has_symbol;
   bool   has_side;
   bool   has_risk_percent;
   bool   has_dry_run;
   bool   has_stop_loss;
   bool   has_market_validation_settings;
   bool   has_equity;
   bool   has_max_risk_percent;
   bool   has_risk_amount;
   bool   has_loss_per_lot;
   bool   has_raw_volume;
   bool   has_volume;
   bool   has_estimated_loss;
   bool   has_estimated_profit_at_sl;
   bool   has_volume_constraints;
   bool   has_max_volume;
   bool   has_volume_normalized_down;
   bool   has_execution_check_settings;
   bool   has_live_execution_settings;
   bool   has_trade_request;
   bool   has_order_check_result;
   bool   has_order_send_result;
   bool   has_last_error_diagnostics;
   bool   has_bid;
   bool   has_ask;
   bool   has_entry_price_reference;
   bool   has_spread_points;
   bool   has_stop_level_points;
   bool   has_point;
   bool   has_digits;
   double bid;
   double ask;
   double entry_price_reference;
   int    spread_points;
   int    stop_level_points;
   double point;
   int    digits;
   string allowed_symbols;
   int    reject_if_spread_above_points;
   double equity;
   double max_risk_percent;
   double risk_amount;
   double loss_per_lot;
   double raw_volume;
   double volume;
   double estimated_loss;
   double estimated_profit_at_sl;
   double volume_min;
   double volume_max;
   double volume_step;
   double max_volume;
   bool   volume_normalized_down;
   bool   enable_order_check;
   int    max_deviation_points;
   bool   enable_live_trading;
   bool   allow_live_order_send;
   bool   live_trading_acknowledgement_valid;
   bool   order_send_attempted;
   bool   persistent_idempotency_enabled;
   bool   audit_log_enabled;
   bool   persistent_duplicate;
   bool   audit_write_failed;
   bool   state_write_failed;
   bool   has_command_state_path;
   bool   has_previous_state;
   bool   has_previous_status;
   bool   has_previous_code;
   bool   has_previous_order_send_attempted;
   bool   has_command_claimed_at_local;
   bool   has_command_finalized_at_local;
   bool   has_trace_id;
   string request_action;
   string request_type;
   string request_symbol;
   double request_volume;
   double request_price;
   double request_sl;
   double request_tp;
   int    request_deviation;
   int    request_magic;
   string request_type_time;
   string request_type_filling;
   bool   order_check_call_success;
   long   order_check_retcode;
   string order_check_comment;
   double order_check_balance;
   double order_check_equity;
   double order_check_profit;
   double order_check_margin;
   double order_check_margin_free;
   double order_check_margin_level;
   bool   order_send_call_success;
   long   order_send_retcode;
   string order_send_comment;
   ulong  order_send_order;
   ulong  order_send_deal;
   double order_send_volume;
   double order_send_price;
   double order_send_bid;
   double order_send_ask;
   int    last_error;
   string last_error_description;
   string command_state_path;
   string previous_state;
   string previous_status;
   string previous_code;
   bool   previous_order_send_attempted;
   string command_claimed_at_local;
   string command_finalized_at_local;
   string trace_id;
};

ProcessedCommandCacheEntry g_processed_command_cache[];

bool CommonFolderAcceptsFile(const string folder_path, int &probe_error);
bool FinalizeCommand(const string command_id,
                     const string status,
                     const string code,
                     const string message,
                     CommandData &command,
                     const string received_at_local,
                     const string archive_folder,
                     const bool remember_result);

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

string JsonDouble(const double value, const int digits)
{
   return DoubleToString(value, digits);
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

bool JsonFieldExists(const string json, const string key)
{
   int position = 0;
   return JsonFindValueStart(json, key, position);
}

bool IsJsonValueTerminator(const ushort ch)
{
   return ch == 44 || ch == 125 || ch == 93 || ch == 32 || ch == 9 || ch == 10 || ch == 13;
}

bool IsDigitChar(const ushort ch)
{
   return ch >= 48 && ch <= 57;
}

bool JsonExtractRawToken(const string json, const string key, string &token)
{
   int position = 0;
   token = "";
   if(!JsonFindValueStart(json, key, position))
      return false;

   const int length = StringLen(json);
   while(position < length)
   {
      const ushort ch = StringGetCharacter(json, position);
      if(IsJsonValueTerminator(ch))
         break;

      token += ShortToString(ch);
      position++;
   }

   return token != "";
}

bool IsStrictIntegerToken(const string token)
{
   const int length = StringLen(token);
   if(length <= 0)
      return false;

   int start = 0;
   const ushort first = StringGetCharacter(token, 0);
   if(first == 43 || first == 45)
   {
      if(length == 1)
         return false;
      start = 1;
   }

   for(int i = start; i < length; i++)
   {
      if(!IsDigitChar(StringGetCharacter(token, i)))
         return false;
   }

   return true;
}

bool IsStrictNumberToken(const string token)
{
   const int length = StringLen(token);
   if(length <= 0)
      return false;

   bool has_digit = false;
   bool has_decimal = false;
   int start = 0;

   const ushort first = StringGetCharacter(token, 0);
   if(first == 43 || first == 45)
   {
      if(length == 1)
         return false;
      start = 1;
   }

   for(int i = start; i < length; i++)
   {
      const ushort ch = StringGetCharacter(token, i);
      if(IsDigitChar(ch))
      {
         has_digit = true;
         continue;
      }

      if(ch == 46 && !has_decimal)
      {
         has_decimal = true;
         continue;
      }

      return false;
   }

   return has_digit;
}

bool JsonExtractInt(const string json, const string key, int &value)
{
   string token = "";
   if(!JsonExtractRawToken(json, key, token))
      return false;

   if(!IsStrictIntegerToken(token))
      return false;

   value = (int)StringToInteger(token);
   return true;
}

bool JsonExtractDoubleNumber(const string json, const string key, double &value)
{
   string token = "";
   if(!JsonExtractRawToken(json, key, token))
      return false;

   if(!IsStrictNumberToken(token))
      return false;

   value = StringToDouble(token);
   return true;
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
      const int terminator_position = position + 4;
      if(terminator_position < StringLen(json) && !IsJsonValueTerminator(StringGetCharacter(json, terminator_position)))
         return false;

      value = true;
      return true;
   }

   if(StringSubstr(json, position, 5) == "false")
   {
      const int terminator_position = position + 5;
      if(terminator_position < StringLen(json) && !IsJsonValueTerminator(StringGetCharacter(json, terminator_position)))
         return false;

      value = false;
      return true;
   }

   return false;
}

string CompactLocalTimestamp()
{
   string value = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
   StringReplace(value, ".", "");
   StringReplace(value, ":", "");
   StringReplace(value, " ", "-");
   return value;
}

string BuildTraceId(const string command_id)
{
   return "trace-" + command_id + "-" + CompactLocalTimestamp() + "-" + IntegerToString((long)g_heartbeat_counter);
}

bool ParseIsoUtcSeconds(const string value, datetime &parsed_utc)
{
   parsed_utc = 0;

   // The extension emits UTC in YYYY-MM-DDTHH:MM:SS.mmmZ form. MQL5 has no
   // direct ISO-8601 UTC parser, so this validates the expected UTC shape,
   // ignores milliseconds, and compares the resulting timestamp to TimeGMT().
   if(StringLen(value) < 20)
      return false;

   if(StringGetCharacter(value, 4) != 45 ||
      StringGetCharacter(value, 7) != 45 ||
      StringGetCharacter(value, 10) != 84 ||
      StringGetCharacter(value, 13) != 58 ||
      StringGetCharacter(value, 16) != 58)
      return false;

   if(StringGetCharacter(value, StringLen(value) - 1) != 90)
      return false;

   const string year_text = StringSubstr(value, 0, 4);
   const string month_text = StringSubstr(value, 5, 2);
   const string day_text = StringSubstr(value, 8, 2);
   const string hour_text = StringSubstr(value, 11, 2);
   const string minute_text = StringSubstr(value, 14, 2);
   const string second_text = StringSubstr(value, 17, 2);

   if(!IsStrictIntegerToken(year_text) ||
      !IsStrictIntegerToken(month_text) ||
      !IsStrictIntegerToken(day_text) ||
      !IsStrictIntegerToken(hour_text) ||
      !IsStrictIntegerToken(minute_text) ||
      !IsStrictIntegerToken(second_text))
      return false;

   const int month = (int)StringToInteger(month_text);
   const int day = (int)StringToInteger(day_text);
   const int hour = (int)StringToInteger(hour_text);
   const int minute = (int)StringToInteger(minute_text);
   const int second = (int)StringToInteger(second_text);

   if(month < 1 || month > 12 || day < 1 || day > 31 ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59)
      return false;

   const string mql_time = year_text + "." + month_text + "." + day_text + " " +
                           hour_text + ":" + minute_text + ":" + second_text;
   parsed_utc = StringToTime(mql_time);
   return parsed_utc > 0;
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
      "logs",
      "state",
      "state\\commands",
      "audit"
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

bool AppendCommonTextFile(const string file_path, const string content)
{
   ResetLastError();

   if(!FileIsExist(file_path, FILE_COMMON))
      return WriteCommonTextFile(file_path, content);

   const int handle = FileOpen(file_path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      LogLastError("FileOpen(" + file_path + ")");
      return false;
   }

   FileSeek(handle, 0, SEEK_END);
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

void ResetCommandData(CommandData &command)
{
   command.type = "";
   command.id = "";
   command.created_at = "";
   command.ttl_ms = 0;
   command.symbol = "";
   command.side = "";
   command.risk_percent = 0.0;
   command.stop_loss = 0.0;
   command.take_profit = 0.0;
   command.dry_run = false;
   command.comment = "";
   command.client_version = "";
   command.source = "";
   command.has_take_profit = false;
   command.has_comment = false;
   command.has_client_version = false;
   command.has_source = false;
   command.has_symbol = false;
   command.has_side = false;
   command.has_risk_percent = false;
   command.has_dry_run = false;
   command.has_stop_loss = false;
   command.has_market_validation_settings = false;
   command.has_equity = false;
   command.has_max_risk_percent = false;
   command.has_risk_amount = false;
   command.has_loss_per_lot = false;
   command.has_raw_volume = false;
   command.has_volume = false;
   command.has_estimated_loss = false;
   command.has_estimated_profit_at_sl = false;
   command.has_volume_constraints = false;
   command.has_max_volume = false;
   command.has_volume_normalized_down = false;
   command.has_execution_check_settings = false;
   command.has_live_execution_settings = true;
   command.has_trade_request = false;
   command.has_order_check_result = false;
   command.has_order_send_result = false;
   command.has_last_error_diagnostics = false;
   command.has_bid = false;
   command.has_ask = false;
   command.has_entry_price_reference = false;
   command.has_spread_points = false;
   command.has_stop_level_points = false;
   command.has_point = false;
   command.has_digits = false;
   command.bid = 0.0;
   command.ask = 0.0;
   command.entry_price_reference = 0.0;
   command.spread_points = 0;
   command.stop_level_points = 0;
   command.point = 0.0;
   command.digits = 0;
   command.allowed_symbols = "";
   command.reject_if_spread_above_points = 0;
   command.equity = 0.0;
   command.max_risk_percent = 0.0;
   command.risk_amount = 0.0;
   command.loss_per_lot = 0.0;
   command.raw_volume = 0.0;
   command.volume = 0.0;
   command.estimated_loss = 0.0;
   command.estimated_profit_at_sl = 0.0;
   command.volume_min = 0.0;
   command.volume_max = 0.0;
   command.volume_step = 0.0;
   command.max_volume = 0.0;
   command.volume_normalized_down = false;
   command.enable_order_check = false;
   command.max_deviation_points = 0;
   command.enable_live_trading = EnableLiveTrading;
   command.allow_live_order_send = AllowLiveOrderSend;
   command.live_trading_acknowledgement_valid = (LiveTradingAcknowledgement == LIVE_TRADING_ACKNOWLEDGEMENT);
   command.order_send_attempted = false;
   command.persistent_idempotency_enabled = EnablePersistentIdempotency;
   command.audit_log_enabled = EnableAuditLog;
   command.persistent_duplicate = false;
   command.audit_write_failed = false;
   command.state_write_failed = false;
   command.has_command_state_path = false;
   command.has_previous_state = false;
   command.has_previous_status = false;
   command.has_previous_code = false;
   command.has_previous_order_send_attempted = false;
   command.has_command_claimed_at_local = false;
   command.has_command_finalized_at_local = false;
   command.has_trace_id = false;
   command.request_action = "";
   command.request_type = "";
   command.request_symbol = "";
   command.request_volume = 0.0;
   command.request_price = 0.0;
   command.request_sl = 0.0;
   command.request_tp = 0.0;
   command.request_deviation = 0;
   command.request_magic = 0;
   command.request_type_time = "";
   command.request_type_filling = "";
   command.order_check_call_success = false;
   command.order_check_retcode = 0;
   command.order_check_comment = "";
   command.order_check_balance = 0.0;
   command.order_check_equity = 0.0;
   command.order_check_profit = 0.0;
   command.order_check_margin = 0.0;
   command.order_check_margin_free = 0.0;
   command.order_check_margin_level = 0.0;
   command.order_send_call_success = false;
   command.order_send_retcode = 0;
   command.order_send_comment = "";
   command.order_send_order = 0;
   command.order_send_deal = 0;
   command.order_send_volume = 0.0;
   command.order_send_price = 0.0;
   command.order_send_bid = 0.0;
   command.order_send_ask = 0.0;
   command.last_error = 0;
   command.last_error_description = "";
   command.command_state_path = "";
   command.previous_state = "";
   command.previous_status = "";
   command.previous_code = "";
   command.previous_order_send_attempted = false;
   command.command_claimed_at_local = "";
   command.command_finalized_at_local = "";
   command.trace_id = "";
}

string BuildResponseJson(const string command_id,
                         const string status,
                         const string code,
                         const string message,
                         CommandData &command,
                         const string received_at_local,
                         const string processed_at_local)
{
   string json = "{\n";
   json += "  \"type\": \"trade.response\",\n";
   json += "  \"id\": " + JsonString(command_id) + ",\n";
   json += "  \"status\": " + JsonString(status) + ",\n";
   json += "  \"code\": " + JsonString(code) + ",\n";
   json += "  \"message\": " + JsonString(message) + ",\n";
   json += "  \"ea_phase\": " + JsonString(EA_PHASE) + ",\n";
   json += "  \"persistent_idempotency_enabled\": " + (command.persistent_idempotency_enabled ? "true" : "false") + ",\n";
   json += "  \"audit_log_enabled\": " + (command.audit_log_enabled ? "true" : "false") + ",\n";

   if(command.persistent_duplicate)
      json += "  \"persistent_duplicate\": true,\n";
   if(command.has_command_state_path)
      json += "  \"command_state_path\": " + JsonString(command.command_state_path) + ",\n";
   if(command.has_previous_state)
      json += "  \"previous_state\": " + JsonString(command.previous_state) + ",\n";
   if(command.has_previous_status)
      json += "  \"previous_status\": " + JsonString(command.previous_status) + ",\n";
   if(command.has_previous_code)
      json += "  \"previous_code\": " + JsonString(command.previous_code) + ",\n";
   if(command.has_previous_order_send_attempted)
      json += "  \"previous_order_send_attempted\": " + (command.previous_order_send_attempted ? "true" : "false") + ",\n";
   if(command.has_command_claimed_at_local)
      json += "  \"command_claimed_at_local\": " + JsonString(command.command_claimed_at_local) + ",\n";
   if(command.has_command_finalized_at_local)
      json += "  \"command_finalized_at_local\": " + JsonString(command.command_finalized_at_local) + ",\n";
   if(command.audit_write_failed)
      json += "  \"audit_write_failed\": true,\n";
   if(command.state_write_failed)
      json += "  \"state_write_failed\": true,\n";

   if(command.has_symbol)
      json += "  \"symbol\": " + JsonString(command.symbol) + ",\n";
   if(command.has_side)
      json += "  \"side\": " + JsonString(command.side) + ",\n";
   if(command.has_risk_percent)
      json += "  \"risk_percent\": " + JsonDouble(command.risk_percent, 6) + ",\n";
   if(command.has_dry_run)
      json += "  \"dry_run\": " + (command.dry_run ? "true" : "false") + ",\n";
   if(command.has_source)
      json += "  \"source\": " + JsonString(command.source) + ",\n";
   if(command.has_comment)
      json += "  \"comment\": " + JsonString(command.comment) + ",\n";
   if(command.has_bid)
      json += "  \"bid\": " + JsonDouble(command.bid, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_ask)
      json += "  \"ask\": " + JsonDouble(command.ask, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_entry_price_reference)
      json += "  \"entry_price_reference\": " + JsonDouble(command.entry_price_reference, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_spread_points)
      json += "  \"spread_points\": " + IntegerToString(command.spread_points) + ",\n";
   if(command.has_stop_level_points)
      json += "  \"stop_level_points\": " + IntegerToString(command.stop_level_points) + ",\n";
   if(command.has_point)
      json += "  \"point\": " + JsonDouble(command.point, 10) + ",\n";
   if(command.has_digits)
      json += "  \"digits\": " + IntegerToString(command.digits) + ",\n";
   if(command.has_stop_loss)
      json += "  \"stop_loss\": " + JsonDouble(command.stop_loss, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_take_profit)
      json += "  \"take_profit\": " + JsonDouble(command.take_profit, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_market_validation_settings)
   {
      json += "  \"allowed_symbols\": " + JsonString(command.allowed_symbols) + ",\n";
      json += "  \"reject_if_spread_above_points\": " + IntegerToString(command.reject_if_spread_above_points) + ",\n";
   }
   if(command.has_equity)
      json += "  \"equity\": " + JsonDouble(command.equity, 2) + ",\n";
   if(command.has_max_risk_percent)
      json += "  \"max_risk_percent\": " + JsonDouble(command.max_risk_percent, 6) + ",\n";
   if(command.has_risk_amount)
      json += "  \"risk_amount\": " + JsonDouble(command.risk_amount, 2) + ",\n";
   if(command.has_loss_per_lot)
   {
      json += "  \"calculation_method\": \"OrderCalcProfit\",\n";
      json += "  \"loss_per_lot\": " + JsonDouble(command.loss_per_lot, 2) + ",\n";
   }
   if(command.has_raw_volume)
      json += "  \"raw_volume\": " + JsonDouble(command.raw_volume, 8) + ",\n";
   if(command.has_volume)
      json += "  \"volume\": " + JsonDouble(command.volume, 8) + ",\n";
   if(command.has_estimated_loss)
      json += "  \"estimated_loss\": " + JsonDouble(command.estimated_loss, 2) + ",\n";
   if(command.has_estimated_profit_at_sl)
      json += "  \"estimated_profit_at_sl\": " + JsonDouble(command.estimated_profit_at_sl, 2) + ",\n";
   if(command.has_volume_constraints)
   {
      json += "  \"volume_min\": " + JsonDouble(command.volume_min, 8) + ",\n";
      json += "  \"volume_max\": " + JsonDouble(command.volume_max, 8) + ",\n";
      json += "  \"volume_step\": " + JsonDouble(command.volume_step, 8) + ",\n";
   }
   if(command.has_max_volume)
      json += "  \"max_volume\": " + JsonDouble(command.max_volume, 8) + ",\n";
   if(command.has_volume_normalized_down)
      json += "  \"volume_normalized_down\": " + (command.volume_normalized_down ? "true" : "false") + ",\n";
   if(command.has_execution_check_settings)
   {
      json += "  \"enable_order_check\": " + (command.enable_order_check ? "true" : "false") + ",\n";
      json += "  \"max_deviation_points\": " + IntegerToString(command.max_deviation_points) + ",\n";
   }
   if(command.has_live_execution_settings)
   {
      json += "  \"enable_live_trading\": " + (command.enable_live_trading ? "true" : "false") + ",\n";
      json += "  \"allow_live_order_send\": " + (command.allow_live_order_send ? "true" : "false") + ",\n";
      json += "  \"live_trading_acknowledgement_valid\": " + (command.live_trading_acknowledgement_valid ? "true" : "false") + ",\n";
      json += "  \"order_send_attempted\": " + (command.order_send_attempted ? "true" : "false") + ",\n";
      json += "  \"order_send_call_success\": " + (command.order_send_call_success ? "true" : "false") + ",\n";
      json += "  \"order_send_retcode\": " + IntegerToString(command.order_send_retcode) + ",\n";
      json += "  \"order_send_comment\": " + JsonString(command.order_send_comment) + ",\n";
      json += "  \"order_send_order\": " + IntegerToString(command.order_send_order) + ",\n";
      json += "  \"order_send_deal\": " + IntegerToString(command.order_send_deal) + ",\n";
      json += "  \"order_send_volume\": " + JsonDouble(command.order_send_volume, 8) + ",\n";
      json += "  \"order_send_price\": " + JsonDouble(command.order_send_price, command.has_digits ? command.digits : 8) + ",\n";
      json += "  \"order_send_bid\": " + JsonDouble(command.order_send_bid, command.has_digits ? command.digits : 8) + ",\n";
      json += "  \"order_send_ask\": " + JsonDouble(command.order_send_ask, command.has_digits ? command.digits : 8) + ",\n";
   }
   if(command.has_trade_request)
   {
      json += "  \"request_action\": " + JsonString(command.request_action) + ",\n";
      json += "  \"request_type\": " + JsonString(command.request_type) + ",\n";
      json += "  \"request_symbol\": " + JsonString(command.request_symbol) + ",\n";
      json += "  \"request_volume\": " + JsonDouble(command.request_volume, 8) + ",\n";
      json += "  \"request_price\": " + JsonDouble(command.request_price, command.has_digits ? command.digits : 8) + ",\n";
      json += "  \"request_sl\": " + JsonDouble(command.request_sl, command.has_digits ? command.digits : 8) + ",\n";
      json += "  \"request_tp\": " + JsonDouble(command.request_tp, command.has_digits ? command.digits : 8) + ",\n";
      json += "  \"request_deviation\": " + IntegerToString(command.request_deviation) + ",\n";
      json += "  \"request_magic\": " + IntegerToString(command.request_magic) + ",\n";
      json += "  \"request_type_time\": " + JsonString(command.request_type_time) + ",\n";
      json += "  \"request_type_filling\": " + JsonString(command.request_type_filling) + ",\n";
   }
   if(command.has_order_check_result)
   {
      json += "  \"order_check_call_success\": " + (command.order_check_call_success ? "true" : "false") + ",\n";
      json += "  \"order_check_retcode\": " + IntegerToString(command.order_check_retcode) + ",\n";
      json += "  \"order_check_comment\": " + JsonString(command.order_check_comment) + ",\n";
      json += "  \"order_check_balance\": " + JsonDouble(command.order_check_balance, 2) + ",\n";
      json += "  \"order_check_equity\": " + JsonDouble(command.order_check_equity, 2) + ",\n";
      json += "  \"order_check_profit\": " + JsonDouble(command.order_check_profit, 2) + ",\n";
      json += "  \"order_check_margin\": " + JsonDouble(command.order_check_margin, 2) + ",\n";
      json += "  \"order_check_margin_free\": " + JsonDouble(command.order_check_margin_free, 2) + ",\n";
      json += "  \"order_check_margin_level\": " + JsonDouble(command.order_check_margin_level, 2) + ",\n";
   }
   if(command.has_last_error_diagnostics)
   {
      json += "  \"last_error\": " + IntegerToString(command.last_error) + ",\n";
      json += "  \"last_error_description\": " + JsonString(command.last_error_description) + ",\n";
   }

   if(!command.has_trace_id)
   {
      command.trace_id = BuildTraceId(command_id);
      command.has_trace_id = true;
   }

   json += "  \"trace_id\": " + JsonString(command.trace_id) + ",\n";
   json += "  \"timestamp_local\": " + JsonString(processed_at_local) + ",\n";
   json += "  \"received_at_local\": " + JsonString(received_at_local) + ",\n";
   json += "  \"processed_at_local\": " + JsonString(processed_at_local) + "\n";
   json += "}\n";
   return json;
}

bool FindProcessedCommand(const string command_id, ProcessedCommandCacheEntry &entry)
{
   for(int i = 0; i < ArraySize(g_processed_command_cache); i++)
   {
      if(g_processed_command_cache[i].id == command_id)
      {
         entry = g_processed_command_cache[i];
         return true;
      }
   }

   return false;
}

bool IsCommandRemembered(const string command_id)
{
   ProcessedCommandCacheEntry entry;
   return FindProcessedCommand(command_id, entry);
}

void RememberCommandResult(const string command_id, const string status, const string code)
{
   if(command_id == "")
      return;

   for(int i = 0; i < ArraySize(g_processed_command_cache); i++)
   {
      if(g_processed_command_cache[i].id == command_id)
      {
         g_processed_command_cache[i].status = status;
         g_processed_command_cache[i].code = code;
         return;
      }
   }

   const int current_size = ArraySize(g_processed_command_cache);
   const int max_cached = g_processed_command_cache_size;

   if(current_size < max_cached)
   {
      ArrayResize(g_processed_command_cache, current_size + 1);
      g_processed_command_cache[current_size].id = command_id;
      g_processed_command_cache[current_size].status = status;
      g_processed_command_cache[current_size].code = code;
      return;
   }

   for(int i = 1; i < max_cached; i++)
      g_processed_command_cache[i - 1] = g_processed_command_cache[i];

   g_processed_command_cache[max_cached - 1].id = command_id;
   g_processed_command_cache[max_cached - 1].status = status;
   g_processed_command_cache[max_cached - 1].code = code;
}

bool IsSafeCommandId(const string command_id)
{
   const int length = StringLen(command_id);
   if(length <= 0 || length > 128)
      return false;

   for(int i = 0; i < length; i++)
   {
      const ushort ch = StringGetCharacter(command_id, i);
      const bool digit = (ch >= 48 && ch <= 57);
      const bool upper = (ch >= 65 && ch <= 90);
      const bool lower = (ch >= 97 && ch <= 122);
      const bool dash = (ch == 45);
      const bool underscore = (ch == 95);

      if(!digit && !upper && !lower && !dash && !underscore)
         return false;
   }

   return true;
}

string CommandStatePath(const string command_id)
{
   return COMMAND_STATE_FOLDER + "\\" + command_id + ".state.json";
}

void EnsureCommandTraceId(const string command_id, CommandData &command)
{
   if(command.has_trace_id)
      return;

   command.trace_id = BuildTraceId(command_id);
   command.has_trace_id = true;
}

void PopulateCommandMetadataForClaim(const string command_json, CommandData &command)
{
   string text_value = "";
   bool bool_value = false;

   if(JsonExtractString(command_json, "symbol", text_value))
   {
      command.symbol = text_value;
      command.has_symbol = true;
   }

   if(JsonExtractString(command_json, "side", text_value))
   {
      command.side = text_value;
      command.has_side = true;
   }

   if(JsonExtractString(command_json, "source", text_value))
   {
      command.source = text_value;
      command.has_source = true;
   }

   if(JsonExtractBool(command_json, "dry_run", bool_value))
   {
      command.dry_run = bool_value;
      command.has_dry_run = true;
   }
}

void PopulatePreviousStateFields(CommandData &command,
                                 const string state_json,
                                 const string state_path)
{
   command.persistent_duplicate = true;
   command.command_state_path = state_path;
   command.has_command_state_path = true;

   if(JsonExtractString(state_json, "state", command.previous_state))
      command.has_previous_state = true;
   if(JsonExtractString(state_json, "final_status", command.previous_status))
      command.has_previous_status = true;
   if(JsonExtractString(state_json, "final_code", command.previous_code))
      command.has_previous_code = true;
   if(JsonExtractBool(state_json, "order_send_attempted", command.previous_order_send_attempted))
      command.has_previous_order_send_attempted = true;
   if(JsonExtractString(state_json, "claimed_at_local", command.command_claimed_at_local))
      command.has_command_claimed_at_local = true;
}

string AuditEventJson(const string event_type,
                      const string command_id,
                      CommandData &command,
                      const string status,
                      const string code,
                      const string archive_destination)
{
   EnsureCommandTraceId(command_id, command);

   string json = "{";
   json += "\"event_type\":" + JsonString(event_type);
   json += ",\"id\":" + JsonString(command_id);
   json += ",\"timestamp_local\":" + JsonString(LocalTimestamp());
   json += ",\"ea_phase\":" + JsonString(EA_PHASE);
   if(status != "")
      json += ",\"status\":" + JsonString(status);
   if(code != "")
      json += ",\"code\":" + JsonString(code);
   if(command.has_symbol)
      json += ",\"symbol\":" + JsonString(command.symbol);
   if(command.has_side)
      json += ",\"side\":" + JsonString(command.side);
   if(command.has_dry_run)
      json += ",\"dry_run\":" + (command.dry_run ? "true" : "false");
   if(command.has_source)
      json += ",\"source\":" + JsonString(command.source);
   if(command.has_trace_id)
      json += ",\"trace_id\":" + JsonString(command.trace_id);
   if(archive_destination != "")
      json += ",\"archive_destination\":" + JsonString(archive_destination);
   if(command.has_live_execution_settings)
      json += ",\"order_send_attempted\":" + (command.order_send_attempted ? "true" : "false");
   if(command.has_order_send_result)
   {
      json += ",\"order_send_retcode\":" + IntegerToString(command.order_send_retcode);
      json += ",\"order_send_order\":" + IntegerToString(command.order_send_order);
      json += ",\"order_send_deal\":" + IntegerToString(command.order_send_deal);
   }
   json += "}";
   return json;
}

bool AppendAuditEvent(const string event_type,
                      const string command_id,
                      CommandData &command,
                      const string status = "",
                      const string code = "",
                      const string archive_destination = "")
{
   if(!EnableAuditLog)
      return true;

   const string line = AuditEventJson(event_type, command_id, command, status, code, archive_destination) + "\n";
   if(AppendCommonTextFile(AUDIT_EVENTS_PATH, line))
      return true;

   command.audit_write_failed = true;
   LogInfo("AUDIT_WRITE_FAILED event_type=" + event_type + " command_id=" + command_id);
   return false;
}

string CommandStateJson(const string command_id,
                        const string state,
                        const string final_status,
                        const string final_code,
                        const string final_message,
                        CommandData &command,
                        const string finalized_at_local,
                        const string archive_destination)
{
   EnsureCommandTraceId(command_id, command);

   string json = "{\n";
   json += "  \"type\": \"command_state\",\n";
   json += "  \"id\": " + JsonString(command_id) + ",\n";
   json += "  \"state\": " + JsonString(state) + ",\n";
   if(final_status != "")
      json += "  \"final_status\": " + JsonString(final_status) + ",\n";
   if(final_code != "")
      json += "  \"final_code\": " + JsonString(final_code) + ",\n";
   if(final_message != "")
      json += "  \"final_message\": " + JsonString(final_message) + ",\n";
   json += "  \"ea_phase\": " + JsonString(EA_PHASE) + ",\n";
   if(command.has_command_claimed_at_local)
      json += "  \"claimed_at_local\": " + JsonString(command.command_claimed_at_local) + ",\n";
   if(finalized_at_local != "")
      json += "  \"finalized_at_local\": " + JsonString(finalized_at_local) + ",\n";
   if(command.has_symbol)
      json += "  \"symbol\": " + JsonString(command.symbol) + ",\n";
   if(command.has_side)
      json += "  \"side\": " + JsonString(command.side) + ",\n";
   if(command.has_dry_run)
      json += "  \"dry_run\": " + (command.dry_run ? "true" : "false") + ",\n";
   if(command.has_source)
      json += "  \"source\": " + JsonString(command.source) + ",\n";
   if(command.has_trace_id)
      json += "  \"trace_id\": " + JsonString(command.trace_id) + ",\n";
   json += "  \"persistent_duplicate\": " + (command.persistent_duplicate ? "true" : "false") + ",\n";
   if(command.has_bid)
      json += "  \"bid\": " + JsonDouble(command.bid, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_ask)
      json += "  \"ask\": " + JsonDouble(command.ask, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_entry_price_reference)
      json += "  \"entry_price_reference\": " + JsonDouble(command.entry_price_reference, command.has_digits ? command.digits : 8) + ",\n";
   if(command.has_spread_points)
      json += "  \"spread_points\": " + IntegerToString(command.spread_points) + ",\n";
   if(command.has_equity)
      json += "  \"equity\": " + JsonDouble(command.equity, 2) + ",\n";
   if(command.has_risk_percent)
      json += "  \"risk_percent\": " + JsonDouble(command.risk_percent, 6) + ",\n";
   if(command.has_risk_amount)
      json += "  \"risk_amount\": " + JsonDouble(command.risk_amount, 2) + ",\n";
   if(command.has_volume)
      json += "  \"volume\": " + JsonDouble(command.volume, 8) + ",\n";
   if(command.has_estimated_loss)
      json += "  \"estimated_loss\": " + JsonDouble(command.estimated_loss, 2) + ",\n";
   json += "  \"enable_live_trading\": " + (command.enable_live_trading ? "true" : "false") + ",\n";
   json += "  \"allow_live_order_send\": " + (command.allow_live_order_send ? "true" : "false") + ",\n";
   json += "  \"live_trading_acknowledgement_valid\": " + (command.live_trading_acknowledgement_valid ? "true" : "false") + ",\n";
   if(command.has_order_check_result)
   {
      json += "  \"order_check_call_success\": " + (command.order_check_call_success ? "true" : "false") + ",\n";
      json += "  \"order_check_retcode\": " + IntegerToString(command.order_check_retcode) + ",\n";
      json += "  \"order_check_comment\": " + JsonString(command.order_check_comment) + ",\n";
   }
   const bool state_order_send_attempted = command.order_send_attempted || state == "order_send_pending";
   json += "  \"order_send_attempted\": " + (state_order_send_attempted ? "true" : "false") + ",\n";
   if(state == "order_send_pending")
      json += "  \"order_send_attempted_at_local\": " + JsonString(LocalTimestamp()) + ",\n";
   if(command.has_order_send_result)
   {
      json += "  \"order_send_call_success\": " + (command.order_send_call_success ? "true" : "false") + ",\n";
      json += "  \"order_send_retcode\": " + IntegerToString(command.order_send_retcode) + ",\n";
      json += "  \"order_send_comment\": " + JsonString(command.order_send_comment) + ",\n";
      json += "  \"order_send_order\": " + IntegerToString(command.order_send_order) + ",\n";
      json += "  \"order_send_deal\": " + IntegerToString(command.order_send_deal) + ",\n";
   }
   if(archive_destination != "")
      json += "  \"archive_destination\": " + JsonString(archive_destination) + ",\n";
   json += "  \"updated_at_local\": " + JsonString(LocalTimestamp()) + "\n";
   json += "}\n";
   return json;
}

bool WriteCommandState(const string command_id,
                       const string state,
                       const string final_status,
                       const string final_code,
                       const string final_message,
                       CommandData &command,
                       const string finalized_at_local,
                       const string archive_destination)
{
   if(!EnablePersistentIdempotency)
      return true;

   const string state_path = CommandStatePath(command_id);
   command.command_state_path = state_path;
   command.has_command_state_path = true;

   const string state_json = CommandStateJson(command_id,
                                             state,
                                             final_status,
                                             final_code,
                                             final_message,
                                             command,
                                             finalized_at_local,
                                             archive_destination);
   if(WriteCommonTextFile(state_path, state_json))
      return true;

   command.state_write_failed = true;
   AppendAuditEvent("state_write_failed", command_id, command, "rejected", "COMMAND_STATE_WRITE_FAILED", archive_destination);
   LogInfo("COMMAND_STATE_WRITE_FAILED command_id=" + command_id + " state_path=" + state_path);
   return false;
}

bool ClaimPersistentCommand(const string command_id,
                            CommandData &command,
                            const string received_at_local)
{
   if(!EnablePersistentIdempotency)
      return true;

   const string state_path = CommandStatePath(command_id);
   command.command_state_path = state_path;
   command.has_command_state_path = true;

   if(FileIsExist(state_path, FILE_COMMON))
   {
      string state_json = "";
      if(!ReadCommonTextFile(state_path, state_json))
      {
         command.state_write_failed = true;
         FinalizeCommand(command_id,
                         "rejected",
                         "COMMAND_STATE_READ_FAILED",
                         "Command state could not be read safely. No action was taken.",
                         command,
                         received_at_local,
                         FAILED_FOLDER,
                         true);
         return false;
      }

      PopulatePreviousStateFields(command, state_json, state_path);
      AppendAuditEvent("persistent_duplicate_detected", command_id, command, "", "", FAILED_FOLDER);

      if(command.previous_state == "order_send_pending")
      {
         command.previous_order_send_attempted = true;
         command.has_previous_order_send_attempted = true;
         FinalizeCommand(command_id,
                         "rejected",
                         "COMMAND_EXECUTION_STATE_INDETERMINATE",
                         "Command had a previous pending live execution state. No action was taken to avoid duplicate execution.",
                         command,
                         received_at_local,
                         FAILED_FOLDER,
                         false);
         return false;
      }

      if(command.previous_state == "claimed" || command.previous_state == "")
      {
         command.previous_state = "claimed";
         command.has_previous_state = true;
         command.previous_order_send_attempted = false;
         command.has_previous_order_send_attempted = true;
         FinalizeCommand(command_id,
                         "rejected",
                         "COMMAND_ALREADY_CLAIMED",
                         "Command id was already claimed previously and has no final state. No action was taken to avoid duplicate execution.",
                         command,
                         received_at_local,
                         FAILED_FOLDER,
                         false);
         return false;
      }

      FinalizeCommand(command_id,
                      "duplicate",
                      "PERSISTENT_DUPLICATE_COMMAND",
                      "Command id was already processed or claimed by this EA runtime state. No action was taken.",
                      command,
                      received_at_local,
                      FAILED_FOLDER,
                      false);
      return false;
   }

   command.command_claimed_at_local = received_at_local;
   command.has_command_claimed_at_local = true;
   command.order_send_attempted = false;

   if(!WriteCommandState(command_id, "claimed", "", "", "", command, "", ""))
   {
      FinalizeCommand(command_id,
                      "rejected",
                      "COMMAND_STATE_WRITE_FAILED",
                      "Command state could not be written safely. No action was taken.",
                      command,
                      received_at_local,
                      FAILED_FOLDER,
                      true);
      return false;
   }

   if(!AppendAuditEvent("command_claimed", command_id, command, "", "", ""))
   {
      FinalizeCommand(command_id,
                      "rejected",
                      "AUDIT_WRITE_FAILED",
                      "Audit log could not be written safely. No action was taken.",
                      command,
                      received_at_local,
                      FAILED_FOLDER,
                      true);
      return false;
   }

   return true;
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
   return IsSafeCommandId(command_id);
}

bool FinalizeCommand(const string command_id,
                     const string status,
                     const string code,
                     const string message,
                     CommandData &command,
                     const string received_at_local,
                     const string archive_folder,
                     const bool remember_result)
{
   string final_status = status;
   string final_code = code;
   string final_message = message;
   string final_archive_folder = archive_folder;
   if(final_status == "accepted")
      final_archive_folder = PROCESSED_FOLDER;
   else if(final_status == "rejected" || final_status == "duplicate")
      final_archive_folder = FAILED_FOLDER;

   const string processed_at_local = LocalTimestamp();
   command.command_finalized_at_local = processed_at_local;
   command.has_command_finalized_at_local = true;

   if(EnablePersistentIdempotency &&
      !command.persistent_duplicate &&
      final_code != "COMMAND_STATE_WRITE_FAILED" &&
      final_code != "COMMAND_STATE_READ_FAILED")
   {
      if(!WriteCommandState(command_id,
                            "final",
                            final_status,
                            final_code,
                            final_message,
                            command,
                            processed_at_local,
                            final_archive_folder))
      {
         if(!command.order_send_attempted)
         {
            final_status = "rejected";
            final_code = "COMMAND_STATE_WRITE_FAILED";
            final_message = "Command state could not be finalized safely. No action was taken.";
            final_archive_folder = FAILED_FOLDER;
         }
      }
   }

   if(final_status == "accepted")
      AppendAuditEvent("command_accepted", command_id, command, final_status, final_code, final_archive_folder);
   else if(final_status == "rejected")
      AppendAuditEvent("command_rejected", command_id, command, final_status, final_code, final_archive_folder);

   const string response_json = BuildResponseJson(command_id,
                                                  final_status,
                                                  final_code,
                                                  final_message,
                                                  command,
                                                  received_at_local,
                                                  processed_at_local);

   if(!WriteResponseFiles(command_id, response_json))
   {
      LogInfo("RESPONSE_WRITE_FAILED for command: " + command_id);
      return false;
   }

   if(!AppendAuditEvent("response_written", command_id, command, final_status, final_code, final_archive_folder))
      LogInfo("AUDIT_WRITE_FAILED after response write for command: " + command_id);

   LogDebug("Final response status=" + final_status +
            " code=" + final_code +
            " command_id=" + command_id +
            " archive_destination=" + final_archive_folder);

   if(remember_result)
      RememberCommandResult(command_id, final_status, final_code);

   if(!ArchiveCommandFiles(command_id, final_archive_folder))
   {
      LogInfo("ARCHIVE_FAILED for command: " + command_id + " destination=" + final_archive_folder);
      return false;
   }

   if(!AppendAuditEvent("command_archived", command_id, command, final_status, final_code, final_archive_folder))
      LogInfo("AUDIT_WRITE_FAILED after archive for command: " + command_id);

   return true;
}

bool RejectCommand(const string command_id,
                   const string code,
                   const string message,
                   CommandData &command,
                   const string received_at_local)
{
   LogInfo("Protocol validation rejected command " + command_id + " code=" + code + " message=" + message);
   return FinalizeCommand(command_id,
                          "rejected",
                          code,
                          message,
                          command,
                          received_at_local,
                          FAILED_FOLDER,
                          true);
}

bool RejectMarketCommand(const string command_id,
                         const string code,
                         const string message,
                         CommandData &command,
                         const string received_at_local)
{
   LogInfo("Market validation rejected command " + command_id + " code=" + code + " message=" + message);
   return FinalizeCommand(command_id,
                          "rejected",
                          code,
                          message,
                          command,
                          received_at_local,
                          FAILED_FOLDER,
                          true);
}

bool FailMarketValidation(const string command_id,
                          const string code,
                          const string message,
                          CommandData &command,
                          const string received_at_local)
{
   RejectMarketCommand(command_id, code, message, command, received_at_local);
   return false;
}

bool RejectRiskCommand(const string command_id,
                       const string code,
                       const string message,
                       CommandData &command,
                       const string received_at_local)
{
   LogInfo("Risk calculation rejected command " + command_id + " code=" + code + " message=" + message);
   return FinalizeCommand(command_id,
                          "rejected",
                          code,
                          message,
                          command,
                          received_at_local,
                          FAILED_FOLDER,
                          true);
}

bool FailRiskCalculation(const string command_id,
                         const string code,
                         const string message,
                         CommandData &command,
                         const string received_at_local)
{
   RejectRiskCommand(command_id, code, message, command, received_at_local);
   return false;
}

bool RejectExecutionCheckCommand(const string command_id,
                                 const string code,
                                 const string message,
                                 CommandData &command,
                                 const string received_at_local)
{
   LogInfo("Execution check rejected command " + command_id + " code=" + code + " message=" + message);
   return FinalizeCommand(command_id,
                          "rejected",
                          code,
                          message,
                          command,
                          received_at_local,
                          FAILED_FOLDER,
                          true);
}

bool FailExecutionCheck(const string command_id,
                        const string code,
                        const string message,
                        CommandData &command,
                        const string received_at_local)
{
   RejectExecutionCheckCommand(command_id, code, message, command, received_at_local);
   return false;
}

string TrimWhitespace(const string value)
{
   int start = 0;
   int end = StringLen(value) - 1;

   while(start <= end)
   {
      const ushort ch = StringGetCharacter(value, start);
      if(ch != 32 && ch != 9 && ch != 10 && ch != 13)
         break;
      start++;
   }

   while(end >= start)
   {
      const ushort ch = StringGetCharacter(value, end);
      if(ch != 32 && ch != 9 && ch != 10 && ch != 13)
         break;
      end--;
   }

   if(end < start)
      return "";

   return StringSubstr(value, start, end - start + 1);
}

string UppercaseCopy(string value)
{
   StringToUpper(value);
   return value;
}

bool IsSymbolAllowedByInput(const string symbol)
{
   const string allowlist = TrimWhitespace(AllowedSymbols);
   if(allowlist == "")
      return true;

   string allowed_items[];
   const ushort comma = StringGetCharacter(",", 0);
   const int item_count = StringSplit(allowlist, comma, allowed_items);
   const string normalized_symbol = UppercaseCopy(TrimWhitespace(symbol));

   for(int i = 0; i < item_count; i++)
   {
      if(UppercaseCopy(TrimWhitespace(allowed_items[i])) == normalized_symbol)
         return true;
   }

   return false;
}

bool HasActiveTakeProfit(CommandData &command)
{
   return command.has_take_profit && command.take_profit != 0.0;
}

double NormalizeVolumeDown(const double volume, const double volume_step)
{
   if(volume <= 0.0 || volume_step <= 0.0)
      return 0.0;

   const double steps = MathFloor(volume / volume_step);
   return NormalizeDouble(steps * volume_step, 8);
}

string SanitizedTradeComment(CommandData &command, const string command_id)
{
   string source = "";
   if(command.has_comment)
      source = TrimWhitespace(command.comment);
   if(source == "")
      source = ProductName + ":" + command_id;

   string sanitized = "";
   const int length = StringLen(source);
   for(int i = 0; i < length; i++)
   {
      const ushort ch = StringGetCharacter(source, i);
      if(ch == 10 || ch == 13 || ch == 9)
         sanitized += " ";
      else if(ch >= 32)
         sanitized += ShortToString(ch);
   }

   sanitized = TrimWhitespace(sanitized);
   if(sanitized == "")
      sanitized = ProductName;

   if(StringLen(sanitized) > 31)
      sanitized = StringSubstr(sanitized, 0, 31);

   return sanitized;
}

bool SelectBrokerFillingMode(const string symbol, ENUM_ORDER_TYPE_FILLING &filling_mode)
{
   long supported_modes = 0;
   ResetLastError();
   if(!SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE, supported_modes))
   {
      LogLastError("SymbolInfoInteger(" + symbol + ",SYMBOL_FILLING_MODE)");
      return false;
   }

   long execution_mode = 0;
   ResetLastError();
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE, execution_mode))
   {
      LogLastError("SymbolInfoInteger(" + symbol + ",SYMBOL_TRADE_EXEMODE)");
      return false;
   }

   if((supported_modes & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
   {
      filling_mode = ORDER_FILLING_FOK;
      return true;
   }

   if((supported_modes & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      filling_mode = ORDER_FILLING_IOC;
      return true;
   }

   if(execution_mode != SYMBOL_TRADE_EXECUTION_MARKET)
   {
      filling_mode = ORDER_FILLING_RETURN;
      return true;
   }

   return false;
}

string TradeActionToString(const ENUM_TRADE_REQUEST_ACTIONS action)
{
   switch(action)
   {
      case TRADE_ACTION_DEAL:
         return "TRADE_ACTION_DEAL";
      case TRADE_ACTION_PENDING:
         return "TRADE_ACTION_PENDING";
      case TRADE_ACTION_SLTP:
         return "TRADE_ACTION_SLTP";
      case TRADE_ACTION_MODIFY:
         return "TRADE_ACTION_MODIFY";
      case TRADE_ACTION_REMOVE:
         return "TRADE_ACTION_REMOVE";
      case TRADE_ACTION_CLOSE_BY:
         return "TRADE_ACTION_CLOSE_BY";
   }

   return "TRADE_ACTION_UNKNOWN";
}

string OrderTypeToString(const ENUM_ORDER_TYPE order_type)
{
   switch(order_type)
   {
      case ORDER_TYPE_BUY:
         return "ORDER_TYPE_BUY";
      case ORDER_TYPE_SELL:
         return "ORDER_TYPE_SELL";
      case ORDER_TYPE_BUY_LIMIT:
         return "ORDER_TYPE_BUY_LIMIT";
      case ORDER_TYPE_SELL_LIMIT:
         return "ORDER_TYPE_SELL_LIMIT";
      case ORDER_TYPE_BUY_STOP:
         return "ORDER_TYPE_BUY_STOP";
      case ORDER_TYPE_SELL_STOP:
         return "ORDER_TYPE_SELL_STOP";
      case ORDER_TYPE_BUY_STOP_LIMIT:
         return "ORDER_TYPE_BUY_STOP_LIMIT";
      case ORDER_TYPE_SELL_STOP_LIMIT:
         return "ORDER_TYPE_SELL_STOP_LIMIT";
      case ORDER_TYPE_CLOSE_BY:
         return "ORDER_TYPE_CLOSE_BY";
   }

   return "ORDER_TYPE_UNKNOWN";
}

string OrderTypeTimeToString(const ENUM_ORDER_TYPE_TIME type_time)
{
   switch(type_time)
   {
      case ORDER_TIME_GTC:
         return "ORDER_TIME_GTC";
      case ORDER_TIME_DAY:
         return "ORDER_TIME_DAY";
      case ORDER_TIME_SPECIFIED:
         return "ORDER_TIME_SPECIFIED";
      case ORDER_TIME_SPECIFIED_DAY:
         return "ORDER_TIME_SPECIFIED_DAY";
   }

   return "ORDER_TIME_UNKNOWN";
}

string OrderFillingToString(const ENUM_ORDER_TYPE_FILLING filling_mode)
{
   switch(filling_mode)
   {
      case ORDER_FILLING_FOK:
         return "ORDER_FILLING_FOK";
      case ORDER_FILLING_IOC:
         return "ORDER_FILLING_IOC";
      case ORDER_FILLING_RETURN:
         return "ORDER_FILLING_RETURN";
      case ORDER_FILLING_BOC:
         return "ORDER_FILLING_BOC";
   }

   return "ORDER_FILLING_UNKNOWN";
}

void StoreTradeRequestPreview(CommandData &command, MqlTradeRequest &request)
{
   command.request_action = TradeActionToString(request.action);
   command.request_type = OrderTypeToString(request.type);
   command.request_symbol = request.symbol;
   command.request_volume = request.volume;
   command.request_price = request.price;
   command.request_sl = request.sl;
   command.request_tp = request.tp;
   command.request_deviation = (int)request.deviation;
   command.request_magic = (int)request.magic;
   command.request_type_time = OrderTypeTimeToString(request.type_time);
   command.request_type_filling = OrderFillingToString(request.type_filling);
   command.has_trade_request = true;
}

string LastErrorDescription(const int error_code)
{
   if(error_code == 0)
      return "No terminal runtime error was reported.";

   return "MT5 runtime error " + IntegerToString(error_code) + ".";
}

void StoreLastErrorDiagnostics(CommandData &command, const int last_error)
{
   command.last_error = last_error;
   command.last_error_description = LastErrorDescription(last_error);
   command.has_last_error_diagnostics = true;
}

void StoreOrderCheckResult(CommandData &command,
                           const bool order_check_call_success,
                           MqlTradeCheckResult &check_result)
{
   command.order_check_call_success = order_check_call_success;
   command.order_check_retcode = (long)check_result.retcode;
   command.order_check_comment = check_result.comment;
   command.order_check_balance = check_result.balance;
   command.order_check_equity = check_result.equity;
   command.order_check_profit = check_result.profit;
   command.order_check_margin = check_result.margin;
   command.order_check_margin_free = check_result.margin_free;
   command.order_check_margin_level = check_result.margin_level;
   command.has_order_check_result = true;
}

void StoreOrderSendResult(CommandData &command,
                          const bool order_send_call_success,
                          MqlTradeResult &send_result)
{
   command.order_send_call_success = order_send_call_success;
   command.order_send_retcode = (long)send_result.retcode;
   command.order_send_comment = send_result.comment;
   command.order_send_order = send_result.order;
   command.order_send_deal = send_result.deal;
   command.order_send_volume = send_result.volume;
   command.order_send_price = send_result.price;
   command.order_send_bid = send_result.bid;
   command.order_send_ask = send_result.ask;
   command.has_order_send_result = true;
}

bool IsSuccessfulTradeRetcode(const long retcode)
{
   return retcode == TRADE_RETCODE_DONE ||
          retcode == TRADE_RETCODE_PLACED ||
          retcode == TRADE_RETCODE_DONE_PARTIAL;
}

bool IsSuccessfulOrderCheckRetcode(const long retcode)
{
   return IsSuccessfulTradeRetcode(retcode);
}

void RefreshLiveExecutionSettings(CommandData &command)
{
   command.enable_live_trading = EnableLiveTrading;
   command.allow_live_order_send = AllowLiveOrderSend;
   command.live_trading_acknowledgement_valid = (LiveTradingAcknowledgement == LIVE_TRADING_ACKNOWLEDGEMENT);
   command.has_live_execution_settings = true;
}

bool ValidateLiveTradingPermissions(const string command_id,
                                    CommandData &command,
                                    const string received_at_local)
{
   const bool terminal_trade_allowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   const bool account_trade_allowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   const bool mql_trade_allowed = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);

   LogInfo("Phase 7 live permission gate command_id=" + command_id +
           " terminal=" + (terminal_trade_allowed ? "true" : "false") +
           " account=" + (account_trade_allowed ? "true" : "false") +
           " mql=" + (mql_trade_allowed ? "true" : "false"));

   if(!terminal_trade_allowed || !mql_trade_allowed)
   {
      return FailExecutionCheck(command_id,
                                "TERMINAL_TRADE_DISABLED",
                                "Terminal or EA automated trading permission is disabled.",
                                command,
                                received_at_local);
   }

   if(!account_trade_allowed)
   {
      return FailExecutionCheck(command_id,
                                "ACCOUNT_TRADE_DISABLED",
                                "Account trading permission is disabled.",
                                command,
                                received_at_local);
   }

   return true;
}

bool RunOrderCheckForCommand(const string command_id,
                             CommandData &command,
                             MqlTradeRequest &request,
                             const string received_at_local)
{
   if(!AppendAuditEvent("order_check_started", command_id, command, "", "", ""))
   {
      return FailExecutionCheck(command_id,
                                "AUDIT_WRITE_FAILED",
                                "Audit log could not be written safely before OrderCheck. No action was taken.",
                                command,
                                received_at_local);
   }

   MqlTradeCheckResult check_result;
   ZeroMemory(check_result);

   ResetLastError();
   const bool check_call_succeeded = OrderCheck(request, check_result);
   const int order_check_last_error = GetLastError();
   StoreOrderCheckResult(command, check_call_succeeded, check_result);
   StoreLastErrorDiagnostics(command, order_check_last_error);

   if(command.order_check_comment == "")
      command.order_check_comment = "OrderCheck returned retcode " + IntegerToString(command.order_check_retcode) + ".";

   LogInfo("Phase 7 OrderCheck command_id=" + command_id +
           " call_success=" + (check_call_succeeded ? "true" : "false") +
           " retcode=" + IntegerToString(command.order_check_retcode) +
           " comment=" + command.order_check_comment);
   LogDebug("OrderCheck diagnostics command_id=" + command_id +
            " last_error=" + IntegerToString(order_check_last_error));

   if(!AppendAuditEvent("order_check_finished", command_id, command, "", "", ""))
   {
      return FailExecutionCheck(command_id,
                                "AUDIT_WRITE_FAILED",
                                "Audit log could not be written safely after OrderCheck. No action was taken.",
                                command,
                                received_at_local);
   }

   if(!check_call_succeeded)
   {
      LogInfo("OrderCheck call failed for command " + command_id +
              " retcode=" + IntegerToString(command.order_check_retcode) +
              " comment=" + command.order_check_comment +
              " last_error=" + IntegerToString(order_check_last_error) +
              ". OrderSend will not be attempted.");
      LogDebug("Final OrderCheck-derived status=rejected code=ORDER_CHECK_FAILED command_id=" + command_id);
      return FailExecutionCheck(command_id,
                                "ORDER_CHECK_FAILED",
                                "MT5 OrderCheck call failed. No trade was executed.",
                                command,
                                received_at_local);
   }

   if(command.order_check_retcode == 0)
   {
      LogInfo("OrderCheck returned ambiguous retcode 0 for command " + command_id +
              " comment=" + command.order_check_comment +
              " last_error=" + IntegerToString(order_check_last_error) +
              ". OrderSend will not be attempted.");
      LogDebug("Final OrderCheck-derived status=rejected code=ORDER_CHECK_FAILED command_id=" + command_id);
      return FailExecutionCheck(command_id,
                                "ORDER_CHECK_FAILED",
                                "MT5 OrderCheck did not produce a valid success or rejection retcode. No trade was executed.",
                                command,
                                received_at_local);
   }

   if(!IsSuccessfulOrderCheckRetcode(command.order_check_retcode))
   {
      LogInfo("OrderCheck rejected command " + command_id +
              " retcode=" + IntegerToString(command.order_check_retcode) +
              " comment=" + command.order_check_comment +
              " last_error=" + IntegerToString(order_check_last_error) +
              ". OrderSend will not be attempted.");
      LogDebug("Final OrderCheck-derived status=rejected code=ORDER_CHECK_REJECTED command_id=" + command_id);
      return FailExecutionCheck(command_id,
                                "ORDER_CHECK_REJECTED",
                                "MT5 OrderCheck rejected the request. No trade was executed.",
                                command,
                                received_at_local);
   }

   LogInfo("OrderCheck passed for command " + command_id +
           " retcode=" + IntegerToString(command.order_check_retcode) +
           " comment=" + command.order_check_comment);
   return true;
}

bool BuildMarketTradeRequest(const string command_id,
                             CommandData &command,
                             MqlTradeRequest &request,
                             const string received_at_local)
{
   ZeroMemory(request);

   ENUM_ORDER_TYPE_FILLING filling_mode = ORDER_FILLING_FOK;
   if(!SelectBrokerFillingMode(command.symbol, filling_mode))
   {
      return FailExecutionCheck(command_id,
                                "ORDER_FILLING_MODE_UNAVAILABLE",
                                "Broker-compatible filling mode could not be determined safely.",
                                command,
                                received_at_local);
   }

   const bool is_buy = (command.side == "buy");
   const double request_price = is_buy ? command.ask : command.bid;
   if(request_price <= 0.0 || command.volume <= 0.0 || command.stop_loss == 0.0)
   {
      return FailExecutionCheck(command_id,
                                "ORDER_REQUEST_BUILD_FAILED",
                                "Trade request preview could not be built from validated command data.",
                                command,
                                received_at_local);
   }

   request.action = TRADE_ACTION_DEAL;
   request.type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.symbol = command.symbol;
   request.volume = command.volume;
   request.price = request_price;
   request.sl = command.stop_loss;
   request.tp = HasActiveTakeProfit(command) ? command.take_profit : 0.0;
   request.deviation = (ulong)MaxDeviationPoints;
   request.magic = (ulong)MagicNumber;
   request.comment = SanitizedTradeComment(command, command_id);
   request.type_time = ORDER_TIME_GTC;
   request.type_filling = filling_mode;

   StoreTradeRequestPreview(command, request);

   LogDebug("Phase 7 request command_id=" + command_id +
            " type=" + command.request_type +
            " price=" + DoubleToString(command.request_price, command.has_digits ? command.digits : 8) +
            " volume=" + DoubleToString(command.request_volume, 8) +
            " sl=" + DoubleToString(command.request_sl, command.has_digits ? command.digits : 8) +
            " tp=" + DoubleToString(command.request_tp, command.has_digits ? command.digits : 8) +
            " filling=" + command.request_type_filling);
   return true;
}

bool RunExecutionCheckForCommand(const string command_id,
                                 CommandData &command,
                                 const string received_at_local,
                                 string &accepted_code,
                                 string &accepted_message)
{
   LogInfo("Phase 7 live execution gate started for command " + command_id + ".");

   command.enable_order_check = EnableOrderCheck;
   command.max_deviation_points = MaxDeviationPoints;
   command.has_execution_check_settings = true;
   RefreshLiveExecutionSettings(command);

   LogInfo("Phase 7 command gates command_id=" + command_id +
           " dry_run=" + (command.dry_run ? "true" : "false") +
           " enable_live_trading=" + (EnableLiveTrading ? "true" : "false") +
           " allow_live_order_send=" + (AllowLiveOrderSend ? "true" : "false") +
           " acknowledgement_valid=" + (command.live_trading_acknowledgement_valid ? "true" : "false") +
           " enable_order_check=" + (EnableOrderCheck ? "true" : "false") +
           " max_deviation_points=" + IntegerToString(MaxDeviationPoints));

   if(MaxDeviationPoints < 0)
   {
      LogInfo("Phase 7 MaxDeviationPoints gate rejected command " + command_id + ".");
      return FailExecutionCheck(command_id,
                                "INVALID_DEVIATION_POINTS",
                                "MaxDeviationPoints must be greater than or equal to 0.",
                                command,
                                received_at_local);
   }

   if(!command.dry_run)
   {
      if(!EnableLiveTrading)
      {
         LogInfo("Phase 7 live gate rejected command " + command_id + " because EnableLiveTrading=false.");
         return FailExecutionCheck(command_id,
                                   "LIVE_TRADING_DISABLED",
                                   "Live trading is disabled by the EnableLiveTrading EA input.",
                                   command,
                                   received_at_local);
      }

      if(!AllowLiveOrderSend)
      {
         LogInfo("Phase 7 live gate rejected command " + command_id + " because AllowLiveOrderSend=false.");
         return FailExecutionCheck(command_id,
                                   "LIVE_ORDER_SEND_DISABLED",
                                   "Live OrderSend is disabled by the AllowLiveOrderSend EA input.",
                                   command,
                                   received_at_local);
      }

      if(!command.live_trading_acknowledgement_valid)
      {
         LogInfo("Phase 7 live gate rejected command " + command_id + " because acknowledgement is missing or invalid.");
         return FailExecutionCheck(command_id,
                                   "LIVE_ACKNOWLEDGEMENT_REQUIRED",
                                   "LiveTradingAcknowledgement must exactly match the required safety acknowledgement.",
                                   command,
                                   received_at_local);
      }

      if(!EnableOrderCheck)
      {
         LogInfo("Phase 7 live gate rejected command " + command_id + " because EnableOrderCheck=false.");
         return FailExecutionCheck(command_id,
                                   "ORDER_CHECK_REQUIRED_FOR_LIVE",
                                   "Live execution requires EnableOrderCheck=true before OrderSend can be attempted.",
                                   command,
                                   received_at_local);
      }

      if(!ValidateLiveTradingPermissions(command_id, command, received_at_local))
         return false;
   }

   MqlTradeRequest request;
   if(!BuildMarketTradeRequest(command_id, command, request, received_at_local))
      return false;

   LogInfo("Phase 7 prepared " + command.request_type +
           " request for command " + command_id +
           " volume=" + DoubleToString(command.request_volume, 8) +
           " price=" + DoubleToString(command.request_price, command.has_digits ? command.digits : 8) +
           " filling=" + command.request_type_filling +
           " dry_run=" + (command.dry_run ? "true" : "false") + ".");

   if(command.dry_run && !EnableOrderCheck)
   {
      LogInfo("Dry-run command " + command_id + " will not call OrderSend. OrderCheck disabled; returning request preview only.");
      accepted_code = "EXECUTION_PREVIEW_READY_NO_TRADE";
      accepted_message = "Command passed validation and risk calculation. Execution request preview was built. No trade was executed in Phase 7.";
      return true;
   }

   if(!RunOrderCheckForCommand(command_id, command, request, received_at_local))
      return false;

   if(command.dry_run)
   {
      LogInfo("Dry-run command " + command_id + " passed OrderCheck. OrderSend will not be attempted.");
      accepted_code = "ORDER_CHECK_PASSED_NO_TRADE";
      accepted_message = "Command passed validation, risk calculation, and MT5 OrderCheck. No trade was executed in Phase 7.";
      LogDebug("Final OrderCheck-derived status=accepted code=" + accepted_code + " command_id=" + command_id);
      return true;
   }

   LogInfo("Phase 7 all live gates passed for command " + command_id + ". OrderSend will be attempted once.");

   MqlTradeResult send_result;
   ZeroMemory(send_result);

   command.order_send_attempted = true;
   if(!WriteCommandState(command_id, "order_send_pending", "", "", "", command, "", ""))
   {
      command.order_send_attempted = false;
      return FailExecutionCheck(command_id,
                                "COMMAND_STATE_WRITE_FAILED",
                                "Command state could not be marked order_send_pending safely. No trade was executed.",
                                command,
                                received_at_local);
   }

   if(!AppendAuditEvent("order_send_pending", command_id, command, "", "", ""))
   {
      command.order_send_attempted = false;
      return FailExecutionCheck(command_id,
                                "AUDIT_WRITE_FAILED",
                                "Audit log could not be written safely before OrderSend. No trade was executed.",
                                command,
                                received_at_local);
   }

   ResetLastError();
   const bool order_send_call_success = OrderSend(request, send_result);
   const int order_send_last_error = GetLastError();
   StoreOrderSendResult(command, order_send_call_success, send_result);
   StoreLastErrorDiagnostics(command, order_send_last_error);

   if(command.order_send_comment == "")
      command.order_send_comment = "OrderSend returned retcode " + IntegerToString(command.order_send_retcode) + ".";

   LogInfo("Phase 7 OrderSend command_id=" + command_id +
           " call_success=" + (order_send_call_success ? "true" : "false") +
           " retcode=" + IntegerToString(command.order_send_retcode) +
           " comment=" + command.order_send_comment +
           " order=" + IntegerToString(command.order_send_order) +
           " deal=" + IntegerToString(command.order_send_deal));
   LogDebug("OrderSend diagnostics command_id=" + command_id +
            " volume=" + DoubleToString(command.order_send_volume, 8) +
            " price=" + DoubleToString(command.order_send_price, command.has_digits ? command.digits : 8) +
            " bid=" + DoubleToString(command.order_send_bid, command.has_digits ? command.digits : 8) +
            " ask=" + DoubleToString(command.order_send_ask, command.has_digits ? command.digits : 8) +
            " last_error=" + IntegerToString(order_send_last_error));

   if(!AppendAuditEvent("order_send_finished", command_id, command, "", "", ""))
      LogInfo("AUDIT_WRITE_FAILED after OrderSend for command: " + command_id);

   if(!order_send_call_success || command.order_send_retcode == 0)
   {
      RememberCommandResult(command_id, "rejected", "ORDER_SEND_FAILED");
      LogInfo("OrderSend failed for command " + command_id +
              " retcode=" + IntegerToString(command.order_send_retcode) +
              " comment=" + command.order_send_comment +
              " last_error=" + IntegerToString(order_send_last_error) + ".");
      return FailExecutionCheck(command_id,
                                "ORDER_SEND_FAILED",
                                "MT5 OrderSend call failed or returned an ambiguous retcode.",
                                command,
                                received_at_local);
   }

   if(!IsSuccessfulTradeRetcode(command.order_send_retcode))
   {
      RememberCommandResult(command_id, "rejected", "ORDER_SEND_REJECTED");
      LogInfo("OrderSend rejected command " + command_id +
              " retcode=" + IntegerToString(command.order_send_retcode) +
              " comment=" + command.order_send_comment +
              " last_error=" + IntegerToString(order_send_last_error) + ".");
      return FailExecutionCheck(command_id,
                                "ORDER_SEND_REJECTED",
                                "MT5 OrderSend rejected the live order request.",
                                command,
                                received_at_local);
   }

   accepted_code = "LIVE_ORDER_SEND_ACCEPTED";
   accepted_message = "Live order request was sent by MT5 OrderSend.";
   RememberCommandResult(command_id, "accepted", accepted_code);
   LogInfo("Phase 7 final status=accepted code=" + accepted_code + " command_id=" + command_id + ".");
   return true;
}

bool CalculateRiskForCommand(const string command_id,
                             CommandData &command,
                             const string received_at_local)
{
   command.max_risk_percent = MaxRiskPercent;
   command.has_max_risk_percent = true;
   command.max_volume = MaxVolume;
   command.has_max_volume = true;

   ResetLastError();
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
   {
      LogDebug("Equity unavailable for command_id=" + command_id + " equity=" + DoubleToString(equity, 2));
      return FailRiskCalculation(command_id,
                                 "EQUITY_UNAVAILABLE",
                                 "Account equity is unavailable.",
                                 command,
                                 received_at_local);
   }

   command.equity = equity;
   command.has_equity = true;

   if(command.risk_percent <= 0.0)
   {
      return FailRiskCalculation(command_id,
                                 "INVALID_RISK_PERCENT",
                                 "Command risk_percent must be positive.",
                                 command,
                                 received_at_local);
   }

   if(command.risk_percent > MaxRiskPercent)
   {
      LogDebug("Risk percent too high command_id=" + command_id +
               " risk_percent=" + DoubleToString(command.risk_percent, 6) +
               " max_risk_percent=" + DoubleToString(MaxRiskPercent, 6));
      return FailRiskCalculation(command_id,
                                 "RISK_PERCENT_TOO_HIGH",
                                 "Command risk_percent exceeds MaxRiskPercent.",
                                 command,
                                 received_at_local);
   }

   const double risk_amount = equity * command.risk_percent / 100.0;
   command.risk_amount = risk_amount;
   command.has_risk_amount = true;

   double profit_at_sl_per_lot = 0.0;
   ENUM_ORDER_TYPE order_type = ORDER_TYPE_SELL;
   if(command.side == "buy")
      order_type = ORDER_TYPE_BUY;

   ResetLastError();
   if(!OrderCalcProfit(order_type,
                       command.symbol,
                       1.0,
                       command.entry_price_reference,
                       command.stop_loss,
                       profit_at_sl_per_lot))
   {
      LogLastError("OrderCalcProfit(1.0," + command.symbol + ")");
      return FailRiskCalculation(command_id,
                                 "ORDER_CALC_PROFIT_FAILED",
                                 "MT5 could not calculate hypothetical stop-loss profit for 1 lot.",
                                 command,
                                 received_at_local);
   }

   const double loss_per_lot = MathAbs(profit_at_sl_per_lot);
   command.loss_per_lot = loss_per_lot;
   command.has_loss_per_lot = true;

   if(loss_per_lot <= 0.0)
   {
      LogDebug("Loss per lot was not positive command_id=" + command_id +
               " profit_at_sl_per_lot=" + DoubleToString(profit_at_sl_per_lot, 2));
      return FailRiskCalculation(command_id,
                                 "STOP_LOSS_LOSS_NOT_POSITIVE",
                                 "Calculated stop-loss loss per lot is not positive.",
                                 command,
                                 received_at_local);
   }

   const double raw_volume = risk_amount / loss_per_lot;
   command.raw_volume = raw_volume;
   command.has_raw_volume = true;

   if(raw_volume <= 0.0)
   {
      return FailRiskCalculation(command_id,
                                 "INVALID_CALCULATED_VOLUME",
                                 "Calculated raw volume is invalid.",
                                 command,
                                 received_at_local);
   }

   double volume_min = 0.0;
   double volume_max = 0.0;
   double volume_step = 0.0;

   if(!SymbolInfoDouble(command.symbol, SYMBOL_VOLUME_MIN, volume_min) ||
      !SymbolInfoDouble(command.symbol, SYMBOL_VOLUME_MAX, volume_max) ||
      !SymbolInfoDouble(command.symbol, SYMBOL_VOLUME_STEP, volume_step) ||
      volume_min <= 0.0 ||
      volume_max < volume_min ||
      volume_step <= 0.0)
   {
      LogDebug("Invalid volume constraints command_id=" + command_id +
               " volume_min=" + DoubleToString(volume_min, 8) +
               " volume_max=" + DoubleToString(volume_max, 8) +
               " volume_step=" + DoubleToString(volume_step, 8));
      return FailRiskCalculation(command_id,
                                 "SYMBOL_VOLUME_CONSTRAINTS_UNAVAILABLE",
                                 "Symbol volume constraints are unavailable or invalid.",
                                 command,
                                 received_at_local);
   }

   command.volume_min = volume_min;
   command.volume_max = volume_max;
   command.volume_step = volume_step;
   command.has_volume_constraints = true;

   double normalized_volume = NormalizeVolumeDown(raw_volume, volume_step);
   command.volume_normalized_down = true;
   command.has_volume_normalized_down = true;

   if(normalized_volume < volume_min)
   {
      LogDebug("Risk too small for min volume command_id=" + command_id +
               " raw_volume=" + DoubleToString(raw_volume, 8) +
               " normalized_volume=" + DoubleToString(normalized_volume, 8) +
               " volume_min=" + DoubleToString(volume_min, 8));
      return FailRiskCalculation(command_id,
                                 "RISK_TOO_SMALL_FOR_MIN_VOLUME",
                                 "Requested risk is too small for the symbol minimum volume.",
                                 command,
                                 received_at_local);
   }

   if(normalized_volume > volume_max)
      normalized_volume = NormalizeVolumeDown(volume_max, volume_step);

   if(MaxVolume > 0.0 && normalized_volume > MaxVolume)
      normalized_volume = NormalizeVolumeDown(MaxVolume, volume_step);

   if(normalized_volume < volume_min)
   {
      LogDebug("Volume cap below min volume command_id=" + command_id +
               " normalized_volume=" + DoubleToString(normalized_volume, 8) +
               " volume_min=" + DoubleToString(volume_min, 8) +
               " max_volume=" + DoubleToString(MaxVolume, 8));
      return FailRiskCalculation(command_id,
                                 "RISK_TOO_SMALL_FOR_MIN_VOLUME",
                                 "Requested risk or configured MaxVolume is below the symbol minimum volume.",
                                 command,
                                 received_at_local);
   }

   command.volume = normalized_volume;
   command.has_volume = true;

   double estimated_profit_at_sl = 0.0;
   ResetLastError();
   if(!OrderCalcProfit(order_type,
                       command.symbol,
                       normalized_volume,
                       command.entry_price_reference,
                       command.stop_loss,
                       estimated_profit_at_sl))
   {
      LogLastError("OrderCalcProfit(" + DoubleToString(normalized_volume, 8) + "," + command.symbol + ")");
      return FailRiskCalculation(command_id,
                                 "ORDER_CALC_PROFIT_FAILED",
                                 "MT5 could not calculate estimated stop-loss profit for normalized volume.",
                                 command,
                                 received_at_local);
   }

   command.estimated_profit_at_sl = estimated_profit_at_sl;
   command.has_estimated_profit_at_sl = true;
   command.estimated_loss = MathAbs(estimated_profit_at_sl);
   command.has_estimated_loss = true;

   const double tolerance = MathMax(0.01, risk_amount * 0.000001);
   if(command.estimated_loss > risk_amount + tolerance)
   {
      LogDebug("Estimated loss exceeds risk command_id=" + command_id +
               " estimated_loss=" + DoubleToString(command.estimated_loss, 2) +
               " risk_amount=" + DoubleToString(risk_amount, 2) +
               " tolerance=" + DoubleToString(tolerance, 6));
      return FailRiskCalculation(command_id,
                                 "ESTIMATED_LOSS_EXCEEDS_RISK",
                                 "Estimated stop-loss loss exceeds requested risk.",
                                 command,
                                 received_at_local);
   }

   LogDebug("Risk calculation command_id=" + command_id +
            " equity=" + DoubleToString(equity, 2) +
            " risk_percent=" + DoubleToString(command.risk_percent, 6) +
            " max_risk_percent=" + DoubleToString(MaxRiskPercent, 6) +
            " risk_amount=" + DoubleToString(risk_amount, 2) +
            " loss_per_lot=" + DoubleToString(loss_per_lot, 2) +
            " raw_volume=" + DoubleToString(raw_volume, 8));
   LogDebug("Volume constraints command_id=" + command_id +
            " volume_min=" + DoubleToString(volume_min, 8) +
            " volume_max=" + DoubleToString(volume_max, 8) +
            " volume_step=" + DoubleToString(volume_step, 8) +
            " max_volume=" + DoubleToString(MaxVolume, 8) +
            " normalized_volume=" + DoubleToString(normalized_volume, 8) +
            " estimated_loss=" + DoubleToString(command.estimated_loss, 2));
   LogInfo("Risk calculation accepted command " + command_id +
           " code=RISK_CALCULATED volume=" + DoubleToString(normalized_volume, 8) +
           " estimated_loss=" + DoubleToString(command.estimated_loss, 2) + ".");
   return true;
}

bool ValidateMarketForCommand(const string command_id,
                              CommandData &command,
                              const string received_at_local)
{
   command.has_market_validation_settings = true;
   command.allowed_symbols = AllowedSymbols;
   command.reject_if_spread_above_points = RejectIfSpreadAbovePoints;

   command.symbol = TrimWhitespace(command.symbol);

   if(!IsSymbolAllowedByInput(command.symbol))
   {
      LogDebug("Symbol allowlist rejected symbol=" + command.symbol + " allowed_symbols=" + AllowedSymbols);
      return FailMarketValidation(command_id,
                                  "SYMBOL_NOT_ALLOWED",
                                  "Command symbol is not included in AllowedSymbols.",
                                  command,
                                  received_at_local);
   }

   ResetLastError();
   if((bool)SymbolInfoInteger(command.symbol, SYMBOL_SELECT))
   {
      LogDebug("Symbol already selected: " + command.symbol);
   }
   else
   {
      ResetLastError();
      if(!SymbolSelect(command.symbol, true))
      {
         LogLastError("SymbolSelect(" + command.symbol + ")");
         return FailMarketValidation(command_id,
                                     "SYMBOL_SELECT_FAILED",
                                     "Command symbol could not be selected in Market Watch.",
                                     command,
                                     received_at_local);
      }

      LogInfo("Symbol selected for market validation: " + command.symbol);
   }

   long digits_raw = 0;
   if(SymbolInfoInteger(command.symbol, SYMBOL_DIGITS, digits_raw))
   {
      command.digits = (int)digits_raw;
      command.has_digits = true;
   }

   double bid = 0.0;
   double ask = 0.0;
   if(!SymbolInfoDouble(command.symbol, SYMBOL_BID, bid) ||
      !SymbolInfoDouble(command.symbol, SYMBOL_ASK, ask) ||
      bid <= 0.0 ||
      ask <= 0.0)
   {
      LogDebug("Bid/ask unavailable for symbol=" + command.symbol +
               " bid=" + DoubleToString(bid, command.has_digits ? command.digits : 8) +
               " ask=" + DoubleToString(ask, command.has_digits ? command.digits : 8));
      return FailMarketValidation(command_id,
                                  "SYMBOL_PRICE_UNAVAILABLE",
                                  "Symbol bid/ask prices are unavailable.",
                                  command,
                                  received_at_local);
   }

   command.bid = bid;
   command.ask = ask;
   command.has_bid = true;
   command.has_ask = true;
   command.entry_price_reference = (command.side == "buy" ? ask : bid);
   command.has_entry_price_reference = true;
   LogDebug("Bid/ask read for " + command.symbol +
            " bid=" + DoubleToString(bid, command.has_digits ? command.digits : 8) +
            " ask=" + DoubleToString(ask, command.has_digits ? command.digits : 8) +
            " entry_reference=" + DoubleToString(command.entry_price_reference, command.has_digits ? command.digits : 8));

   const long trade_mode = SymbolInfoInteger(command.symbol, SYMBOL_TRADE_MODE);
   LogDebug("Symbol trade mode for " + command.symbol + " mode=" + IntegerToString(trade_mode));
   if(trade_mode == SYMBOL_TRADE_MODE_DISABLED)
   {
      return FailMarketValidation(command_id,
                                  "SYMBOL_TRADE_DISABLED",
                                  "Trading is disabled for the command symbol.",
                                  command,
                                  received_at_local);
   }

   const bool terminal_trade_allowed = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   const bool account_trade_allowed = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   const bool mql_trade_allowed = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
   LogDebug("Trade permissions terminal=" + (terminal_trade_allowed ? "true" : "false") +
            " account=" + (account_trade_allowed ? "true" : "false") +
            " mql=" + (mql_trade_allowed ? "true" : "false"));

   if(!terminal_trade_allowed || !mql_trade_allowed)
   {
      return FailMarketValidation(command_id,
                                  "TERMINAL_TRADE_DISABLED",
                                  "Terminal or EA automated trading permission is disabled.",
                                  command,
                                  received_at_local);
   }

   if(!account_trade_allowed)
   {
      return FailMarketValidation(command_id,
                                  "ACCOUNT_TRADE_DISABLED",
                                  "Account trading permission is disabled.",
                                  command,
                                  received_at_local);
   }

   long stop_level_raw = 0;
   if(SymbolInfoInteger(command.symbol, SYMBOL_TRADE_STOPS_LEVEL, stop_level_raw))
   {
      command.stop_level_points = (int)stop_level_raw;
      command.has_stop_level_points = true;
   }

   double point = 0.0;
   if(SymbolInfoDouble(command.symbol, SYMBOL_POINT, point) && point > 0.0)
   {
      command.point = point;
      command.has_point = true;
   }
   LogDebug("Stop level market data for " + command.symbol +
            " stop_level_points=" + (command.has_stop_level_points ? IntegerToString(command.stop_level_points) : "unavailable") +
            " point=" + (command.has_point ? DoubleToString(command.point, 10) : "unavailable"));

   long spread_raw = 0;
   if(SymbolInfoInteger(command.symbol, SYMBOL_SPREAD, spread_raw))
   {
      command.spread_points = (int)spread_raw;
      command.has_spread_points = true;
      LogDebug("Spread read for " + command.symbol + " spread_points=" + IntegerToString(command.spread_points));
   }
   else
   {
      LogDebug("Spread unavailable for " + command.symbol);
   }

   if(command.has_spread_points && RejectIfSpreadAbovePoints > 0 && command.spread_points > RejectIfSpreadAbovePoints)
   {
      return FailMarketValidation(command_id,
                                  "SPREAD_TOO_HIGH",
                                  "Current symbol spread exceeds RejectIfSpreadAbovePoints.",
                                  command,
                                  received_at_local);
   }

   if(command.side == "buy")
   {
      if(command.stop_loss >= ask)
      {
         LogDebug("SL side validation failed for buy command_id=" + command_id +
                  " stop_loss=" + DoubleToString(command.stop_loss, command.has_digits ? command.digits : 8) +
                  " ask=" + DoubleToString(ask, command.has_digits ? command.digits : 8));
         return FailMarketValidation(command_id,
                                     "INVALID_STOP_LOSS",
                                     "Buy stop_loss must be below the current Ask.",
                                     command,
                                     received_at_local);
      }
      LogDebug("SL side validation passed for buy command_id=" + command_id +
               " stop_loss=" + DoubleToString(command.stop_loss, command.has_digits ? command.digits : 8) +
               " ask=" + DoubleToString(ask, command.has_digits ? command.digits : 8));

      if(HasActiveTakeProfit(command) && command.take_profit <= ask)
      {
         LogDebug("TP side validation failed for buy command_id=" + command_id +
                  " take_profit=" + DoubleToString(command.take_profit, command.has_digits ? command.digits : 8) +
                  " ask=" + DoubleToString(ask, command.has_digits ? command.digits : 8));
         return FailMarketValidation(command_id,
                                     "INVALID_TAKE_PROFIT",
                                     "Buy take_profit must be above the current Ask.",
                                     command,
                                     received_at_local);
      }
      LogDebug("TP side validation passed for buy command_id=" + command_id +
               " take_profit=" + (HasActiveTakeProfit(command) ? DoubleToString(command.take_profit, command.has_digits ? command.digits : 8) : "none") +
               " ask=" + DoubleToString(ask, command.has_digits ? command.digits : 8));
   }
   else
   {
      if(command.stop_loss <= bid)
      {
         LogDebug("SL side validation failed for sell command_id=" + command_id +
                  " stop_loss=" + DoubleToString(command.stop_loss, command.has_digits ? command.digits : 8) +
                  " bid=" + DoubleToString(bid, command.has_digits ? command.digits : 8));
         return FailMarketValidation(command_id,
                                     "INVALID_STOP_LOSS",
                                     "Sell stop_loss must be above the current Bid.",
                                     command,
                                     received_at_local);
      }
      LogDebug("SL side validation passed for sell command_id=" + command_id +
               " stop_loss=" + DoubleToString(command.stop_loss, command.has_digits ? command.digits : 8) +
               " bid=" + DoubleToString(bid, command.has_digits ? command.digits : 8));

      if(HasActiveTakeProfit(command) && command.take_profit >= bid)
      {
         LogDebug("TP side validation failed for sell command_id=" + command_id +
                  " take_profit=" + DoubleToString(command.take_profit, command.has_digits ? command.digits : 8) +
                  " bid=" + DoubleToString(bid, command.has_digits ? command.digits : 8));
         return FailMarketValidation(command_id,
                                     "INVALID_TAKE_PROFIT",
                                     "Sell take_profit must be below the current Bid.",
                                     command,
                                     received_at_local);
      }
      LogDebug("TP side validation passed for sell command_id=" + command_id +
               " take_profit=" + (HasActiveTakeProfit(command) ? DoubleToString(command.take_profit, command.has_digits ? command.digits : 8) : "none") +
               " bid=" + DoubleToString(bid, command.has_digits ? command.digits : 8));
   }

   if(command.has_stop_level_points && command.has_point && command.stop_level_points > 0)
   {
      const double minimum_distance = command.stop_level_points * command.point;
      const double sl_distance = MathAbs(command.entry_price_reference - command.stop_loss);

      if(sl_distance < minimum_distance)
      {
         LogDebug("Stop level SL validation failed command_id=" + command_id +
                  " sl_distance=" + DoubleToString(sl_distance, 10) +
                  " minimum_distance=" + DoubleToString(minimum_distance, 10));
         return FailMarketValidation(command_id,
                                     "STOP_LOSS_TOO_CLOSE",
                                     "stop_loss is closer than the broker stop level.",
                                     command,
                                     received_at_local);
      }

      if(HasActiveTakeProfit(command))
      {
         const double tp_distance = MathAbs(command.take_profit - command.entry_price_reference);
         if(tp_distance < minimum_distance)
         {
            LogDebug("Stop level TP validation failed command_id=" + command_id +
                     " tp_distance=" + DoubleToString(tp_distance, 10) +
                     " minimum_distance=" + DoubleToString(minimum_distance, 10));
            return FailMarketValidation(command_id,
                                        "TAKE_PROFIT_TOO_CLOSE",
                                        "take_profit is closer than the broker stop level.",
                                        command,
                                        received_at_local);
         }
      }

      LogDebug("Stop level validation passed command_id=" + command_id +
               " stop_level_points=" + IntegerToString(command.stop_level_points));
   }
   else
   {
      LogDebug("Stop level validation skipped or not required command_id=" + command_id);
   }

   LogInfo("Market validation accepted command " + command_id + ".");
   return true;
}

bool ValidateRequiredField(const string command_json,
                           const string field_name,
                           const string command_id,
                           CommandData &command,
                           const string received_at_local)
{
   if(JsonFieldExists(command_json, field_name))
      return true;

   RejectCommand(command_id,
                 "MISSING_REQUIRED_FIELD",
                 "Command is missing required field: " + field_name + ".",
                 command,
                 received_at_local);
   return false;
}

bool ParseAndValidateCommand(const string command_json,
                             const string command_id,
                             CommandData &command,
                             const string received_at_local)
{
   string required_fields[] =
   {
      "type",
      "id",
      "created_at",
      "ttl_ms",
      "symbol",
      "side",
      "risk_percent",
      "stop_loss",
      "dry_run"
   };

   for(int i = 0; i < ArraySize(required_fields); i++)
   {
      if(!ValidateRequiredField(command_json, required_fields[i], command_id, command, received_at_local))
         return false;
   }

   if(!JsonExtractString(command_json, "type", command.type))
   {
      RejectCommand(command_id, "INVALID_TYPE", "Command type must be the string trade.open.", command, received_at_local);
      return false;
   }

   if(command.type != "trade.open")
   {
      RejectCommand(command_id, "INVALID_TYPE", "Command type must equal trade.open.", command, received_at_local);
      return false;
   }

   if(!JsonExtractString(command_json, "id", command.id))
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command id must be a string.", command, received_at_local);
      return false;
   }

   if(command.id == "")
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command id must not be empty.", command, received_at_local);
      return false;
   }

   if(command.id != command_id)
   {
      RejectCommand(command_id, "ID_MISMATCH", "Command id does not match command filename.", command, received_at_local);
      return false;
   }

   if(!JsonExtractString(command_json, "created_at", command.created_at))
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command created_at must be a string.", command, received_at_local);
      return false;
   }

   if(command.created_at == "")
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command created_at must not be empty.", command, received_at_local);
      return false;
   }

   if(!JsonExtractInt(command_json, "ttl_ms", command.ttl_ms) ||
      command.ttl_ms <= 0 ||
      command.ttl_ms > MaxCommandTtlMs)
   {
      RejectCommand(command_id, "INVALID_TTL", "Command ttl_ms must be positive and must not exceed MaxCommandTtlMs.", command, received_at_local);
      return false;
   }

   if(!JsonExtractString(command_json, "symbol", command.symbol))
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command symbol must be a string.", command, received_at_local);
      return false;
   }
   command.has_symbol = true;

   if(command.symbol == "")
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command symbol must not be empty.", command, received_at_local);
      return false;
   }

   if(!JsonExtractString(command_json, "side", command.side))
   {
      RejectCommand(command_id, "INVALID_SIDE", "Command side must be buy or sell.", command, received_at_local);
      return false;
   }
   command.has_side = true;

   if(command.side != "buy" && command.side != "sell")
   {
      RejectCommand(command_id, "INVALID_SIDE", "Command side must be buy or sell.", command, received_at_local);
      return false;
   }

   if(!JsonExtractDoubleNumber(command_json, "risk_percent", command.risk_percent) ||
      command.risk_percent <= 0.0)
   {
      RejectCommand(command_id, "INVALID_RISK_PERCENT", "Command risk_percent must be positive.", command, received_at_local);
      return false;
   }
   command.has_risk_percent = true;
   LogDebug("Parsed risk_percent for command " + command_id + ": " + DoubleToString(command.risk_percent, 4));

   if(!JsonExtractDoubleNumber(command_json, "stop_loss", command.stop_loss) ||
      command.stop_loss == 0.0)
   {
      RejectCommand(command_id, "INVALID_STOP_LOSS", "Command stop_loss must be present and non-zero.", command, received_at_local);
      return false;
   }
   command.has_stop_loss = true;
   LogDebug("Parsed stop_loss for command " + command_id + ": " + DoubleToString(command.stop_loss, 8));

   if(!JsonExtractBool(command_json, "dry_run", command.dry_run))
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command dry_run must be a boolean.", command, received_at_local);
      return false;
   }
   command.has_dry_run = true;

   if(JsonFieldExists(command_json, "take_profit"))
   {
      if(!JsonExtractDoubleNumber(command_json, "take_profit", command.take_profit))
      {
         RejectCommand(command_id, "INVALID_COMMAND", "Command take_profit must be numeric when present.", command, received_at_local);
         return false;
      }
      command.has_take_profit = true;
      LogDebug("Parsed take_profit for command " + command_id + ": " + DoubleToString(command.take_profit, 8));
   }

   if(JsonFieldExists(command_json, "comment"))
   {
      if(!JsonExtractString(command_json, "comment", command.comment))
      {
         RejectCommand(command_id, "INVALID_COMMAND", "Command comment must be a string when present.", command, received_at_local);
         return false;
      }
      command.has_comment = true;
   }

   if(JsonFieldExists(command_json, "client_version"))
   {
      if(!JsonExtractString(command_json, "client_version", command.client_version))
      {
         RejectCommand(command_id, "INVALID_COMMAND", "Command client_version must be a string when present.", command, received_at_local);
         return false;
      }
      command.has_client_version = true;
   }

   if(JsonFieldExists(command_json, "source"))
   {
      if(!JsonExtractString(command_json, "source", command.source))
      {
         RejectCommand(command_id, "INVALID_COMMAND", "Command source must be a string when present.", command, received_at_local);
         return false;
      }
      command.has_source = true;
   }

   if(EnforceCommandTtl)
   {
      datetime created_utc = 0;
      if(!ParseIsoUtcSeconds(command.created_at, created_utc))
      {
         RejectCommand(command_id, "INVALID_TTL", "Command created_at must use YYYY-MM-DDTHH:MM:SS.mmmZ UTC format.", command, received_at_local);
         return false;
      }

      const datetime now_utc = TimeGMT();
      const long age_seconds = (long)(now_utc - created_utc);
      const long ttl_seconds = (long)((command.ttl_ms + 999) / 1000);

      if(age_seconds > ttl_seconds)
      {
         LogInfo("Expired command detected: " + command_id + " age_seconds=" + IntegerToString(age_seconds) + " ttl_ms=" + IntegerToString(command.ttl_ms));
         RejectCommand(command_id, "COMMAND_EXPIRED", "Command expired before EA processing.", command, received_at_local);
         return false;
      }
   }

   LogInfo("Protocol validation passed for command: " + command_id);
   return true;
}

void ProcessDuplicateCommand(const string command_id, const string received_at_local)
{
   ProcessedCommandCacheEntry previous;
   FindProcessedCommand(command_id, previous);

   CommandData command;
   ResetCommandData(command);
   command.previous_status = previous.status;
   command.previous_code = previous.code;
   command.has_previous_status = (previous.status != "");
   command.has_previous_code = (previous.code != "");

   LogInfo("Duplicate command detected: " + command_id + " previous_status=" + previous.status + " previous_code=" + previous.code);
   FinalizeCommand(command_id,
                   "duplicate",
                   "DUPLICATE_COMMAND",
                   "Command was already processed by this EA session.",
                   command,
                   received_at_local,
                   FAILED_FOLDER,
                   false);
}

void ProcessReadyCommand(const string ready_file_name)
{
   const string received_at_local = LocalTimestamp();

   string command_id = "";
   if(!ReadyFileToCommandId(ready_file_name, command_id))
   {
      LogInfo("Invalid ready filename detected: " + ready_file_name);
      return;
   }

   LogInfo("Command ready file detected: " + INBOX_FOLDER + "\\" + ready_file_name);

   const string command_path = INBOX_FOLDER + "\\" + command_id + ".command.json.tmp";
   CommandData command;
   ResetCommandData(command);

   if(!AppendAuditEvent("command_detected", command_id, command, "", "", ""))
   {
      FinalizeCommand(command_id,
                      "rejected",
                      "AUDIT_WRITE_FAILED",
                      "Audit log could not be written safely. No action was taken.",
                      command,
                      received_at_local,
                      FAILED_FOLDER,
                      true);
      return;
   }

   if(!FileIsExist(command_path, FILE_COMMON))
   {
      LogInfo("COMMAND_FILE_MISSING for command: " + command_id);
      RejectCommand(command_id, "COMMAND_FILE_MISSING", "Command payload file is missing.", command, received_at_local);
      return;
   }

   string command_json = "";
   if(!ReadCommonTextFile(command_path, command_json))
   {
      LogInfo("COMMAND_FILE_READ_FAILED for command: " + command_id);
      RejectCommand(command_id, "COMMAND_FILE_READ_FAILED", "Command payload could not be read.", command, received_at_local);
      return;
   }

   LogInfo("Command file read: " + command_path);
   LogDebug("Command parsed for protocol validation: " + command_id);

   string payload_id = "";
   if(!JsonExtractString(command_json, "id", payload_id) || payload_id == "")
   {
      RejectCommand(command_id, "MISSING_REQUIRED_FIELD", "Command id must be a non-empty string.", command, received_at_local);
      return;
   }

   if(payload_id != command_id)
   {
      RejectCommand(command_id, "ID_MISMATCH", "Command id does not match command filename.", command, received_at_local);
      return;
   }

   PopulateCommandMetadataForClaim(command_json, command);

   if(!ClaimPersistentCommand(command_id, command, received_at_local))
      return;

   if(IsCommandRemembered(command_id))
   {
      ProcessDuplicateCommand(command_id, received_at_local);
      return;
   }

   if(!ParseAndValidateCommand(command_json, command_id, command, received_at_local))
      return;

   if(!ValidateMarketForCommand(command_id, command, received_at_local))
      return;

   if(!CalculateRiskForCommand(command_id, command, received_at_local))
      return;

   string accepted_code = "";
   string accepted_message = "";
   if(!RunExecutionCheckForCommand(command_id, command, received_at_local, accepted_code, accepted_message))
      return;

   FinalizeCommand(command_id,
                   "accepted",
                   accepted_code,
                   accepted_message,
                   command,
                   received_at_local,
                   PROCESSED_FOLDER,
                   true);
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
   json += "  \"ea_phase\": " + JsonString(EA_PHASE) + ",\n";
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
   json += "  \"enforce_command_ttl\": " + (EnforceCommandTtl ? "true" : "false") + ",\n";
   json += "  \"max_command_ttl_ms\": " + IntegerToString(MaxCommandTtlMs) + ",\n";
   json += "  \"processed_command_cache_size\": " + IntegerToString(g_processed_command_cache_size) + ",\n";
   json += "  \"reject_if_spread_above_points\": " + IntegerToString(RejectIfSpreadAbovePoints) + ",\n";
   json += "  \"allowed_symbols\": " + JsonString(AllowedSymbols) + ",\n";
   json += "  \"max_risk_percent\": " + JsonDouble(MaxRiskPercent, 6) + ",\n";
   json += "  \"max_volume\": " + JsonDouble(MaxVolume, 8) + ",\n";
   json += "  \"enable_order_check\": " + (EnableOrderCheck ? "true" : "false") + ",\n";
   json += "  \"max_deviation_points\": " + IntegerToString(MaxDeviationPoints) + ",\n";
   json += "  \"enable_live_trading\": " + (EnableLiveTrading ? "true" : "false") + ",\n";
   json += "  \"allow_live_order_send\": " + (AllowLiveOrderSend ? "true" : "false") + ",\n";
   json += "  \"live_trading_acknowledgement_valid\": " + ((LiveTradingAcknowledgement == LIVE_TRADING_ACKNOWLEDGEMENT) ? "true" : "false") + ",\n";
   json += "  \"persistent_idempotency_enabled\": " + (EnablePersistentIdempotency ? "true" : "false") + ",\n";
   json += "  \"audit_log_enabled\": " + (EnableAuditLog ? "true" : "false") + ",\n";
   json += "  \"state_folder\": " + JsonString(STATE_FOLDER) + ",\n";
   json += "  \"audit_folder\": " + JsonString(AUDIT_FOLDER) + ",\n";
   if(!EnablePersistentIdempotency)
      json += "  \"persistent_idempotency_warning\": \"Persistent idempotency is disabled. Duplicate protection is session-level only.\",\n";
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

   g_processed_command_cache_size = ProcessedCommandCacheSize;
   if(g_processed_command_cache_size < 1)
   {
      LogInfo("ProcessedCommandCacheSize was below 1; using 1 instead.");
      g_processed_command_cache_size = 1;
   }

   LogInfo("Initializing MTChartBridgeEA phase 8.");
   LogInfo("Command TTL enforcement=" + (EnforceCommandTtl ? "true" : "false") +
           " max_ttl_ms=" + IntegerToString(MaxCommandTtlMs) +
           " processed_cache_size=" + IntegerToString(g_processed_command_cache_size) +
           " reject_if_spread_above_points=" + IntegerToString(RejectIfSpreadAbovePoints) +
           " allowed_symbols=" + AllowedSymbols +
           " max_risk_percent=" + DoubleToString(MaxRiskPercent, 6) +
           " max_volume=" + DoubleToString(MaxVolume, 8) +
           " enable_order_check=" + (EnableOrderCheck ? "true" : "false") +
           " max_deviation_points=" + IntegerToString(MaxDeviationPoints) +
           " enable_live_trading=" + (EnableLiveTrading ? "true" : "false") +
           " allow_live_order_send=" + (AllowLiveOrderSend ? "true" : "false") +
           " live_acknowledgement_valid=" + ((LiveTradingAcknowledgement == LIVE_TRADING_ACKNOWLEDGEMENT) ? "true" : "false") +
           " persistent_idempotency_enabled=" + (EnablePersistentIdempotency ? "true" : "false") +
           " audit_log_enabled=" + (EnableAuditLog ? "true" : "false"));
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

   // Phase 8 reads at most one local command per timer tick and blocks previously claimed IDs before trade paths.
   ProcessOneReadyCommand();
}
