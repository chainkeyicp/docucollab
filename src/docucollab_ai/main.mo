import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Char "mo:base/Char";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Error "mo:base/Error";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import LLM "mo:llm";

actor DocuCollabAI {

  // ===== HTTPS OUTCALL TYPES (for premium AI) =====

  public type HttpHeader = { name : Text; value : Text };
  public type HttpMethod = { #get; #post; #head };
  public type TransformContext = {
    function : shared query TransformArgs -> async HttpResponsePayload;
    context : Blob;
  };
  public type HttpRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [HttpHeader];
    body : ?Blob;
    method : HttpMethod;
    transform : ?TransformContext;
  };
  public type HttpResponsePayload = {
    status : Nat;
    headers : [HttpHeader];
    body : Blob;
  };
  public type TransformArgs = {
    response : HttpResponsePayload;
    context : Blob;
  };

  let ic : actor { http_request : HttpRequestArgs -> async HttpResponsePayload } = actor "aaaaa-aa";

  stable var apiKey : Text = "";
  stable var apiUrl : Text = "https://api.anthropic.com/v1/messages";
  stable var adminPrincipal : ?Principal = null;

  let MAX_AI_INPUT_CHARS : Nat = 100_000;

  // ===== HELPERS =====

  func truncateForLLM(content : Text, maxChars : Nat) : Text {
    if (content.size() <= maxChars) { return content };
    let chars = Text.toArray(content);
    let maxCharsInt : Int = maxChars;
    let halfSizeInt = if (maxCharsInt > 60) { (maxCharsInt - 60) / 2 } else { maxCharsInt / 2 };
    let halfSize = Int.abs(halfSizeInt);
    let head = Array.subArray(chars, 0, halfSize);
    let charCountInt : Int = chars.size();
    let tailStart = if (charCountInt > halfSizeInt) { Int.abs(charCountInt - halfSizeInt) } else { 0 };
    let tail = Array.subArray(chars, tailStart, halfSize);
    Text.fromIter(head.vals()) # "\n\n[... document continues ...]\n\n" # Text.fromIter(tail.vals())
  };

  func isTooLargeForAI(content : Text) : Bool {
    content.size() > MAX_AI_INPUT_CHARS
  };

  // ===== ON-CHAIN AI (icp_llm) =====

  public shared(msg) func summarizeOnChain(content : Text) : async Result.Result<Text, Text> {
    if (Principal.isAnonymous(msg.caller)) return #err("Anonymous callers not allowed");
    if (isTooLargeForAI(content)) return #err("Document is too large for AI analysis");
    let trimmed = truncateForLLM(content, 8000);
    try {
      let response = await LLM.prompt(
        #Llama3_1_8B,
        "You are a document summarization assistant. Summarize the following document in 2-3 concise paragraphs. Focus on key points and main ideas:\n\n" # trimmed
      );
      #ok(response)
    } catch (e) {
      #err("On-chain AI error: " # Error.message(e))
    };
  };

  public shared(msg) func chatWithDocument(content : Text, question : Text) : async Result.Result<Text, Text> {
    if (Principal.isAnonymous(msg.caller)) return #err("Anonymous callers not allowed");
    if (isTooLargeForAI(content)) return #err("Document is too large for AI analysis");
    let trimmed = truncateForLLM(content, 7000);
    try {
      let response = await LLM.chat(#Llama3_1_8B).withMessages([
        #system_({ content = "You are a helpful assistant. Answer questions about the following document. Be concise and accurate.\n\nDocument:\n" # trimmed }),
        #user({ content = question })
      ]).send();
      switch (response.message.content) {
        case (?text) #ok(text);
        case null #err("No response from AI");
      };
    } catch (e) {
      #err("On-chain AI error: " # Error.message(e))
    };
  };

  public shared(msg) func extractKeyPoints(content : Text) : async Result.Result<Text, Text> {
    if (Principal.isAnonymous(msg.caller)) return #err("Anonymous callers not allowed");
    if (isTooLargeForAI(content)) return #err("Document is too large for AI analysis");
    let trimmed = truncateForLLM(content, 8000);
    try {
      let response = await LLM.prompt(
        #Llama3_1_8B,
        "Extract the key points from the following document as a bulleted list (use - for each point). Be concise, max 7 points:\n\n" # trimmed
      );
      #ok(response)
    } catch (e) {
      #err("On-chain AI error: " # Error.message(e))
    };
  };

  public shared(msg) func categorizeDocument(content : Text) : async Result.Result<Text, Text> {
    if (Principal.isAnonymous(msg.caller)) return #err("Anonymous callers not allowed");
    if (isTooLargeForAI(content)) return #err("Document is too large for AI analysis");
    let trimmed = truncateForLLM(content, 4000);
    try {
      let response = await LLM.prompt(
        #Llama3_1_8B,
        "Classify the following document into ONE of these categories: Legal, Technical, Financial, Research, Marketing, Personal, Administrative, Creative, Educational, Other. Reply with ONLY the category name, nothing else.\n\n" # trimmed
      );
      #ok(response)
    } catch (e) {
      #err("On-chain AI error: " # Error.message(e))
    };
  };

  // ===== PREMIUM AI (Claude via HTTPS Outcalls) =====

  public query func transform(raw : TransformArgs) : async HttpResponsePayload {
    { status = raw.response.status; body = raw.response.body; headers = [] }
  };

  public shared(msg) func setApiKey(key : Text) : async Result.Result<(), Text> {
    switch (adminPrincipal) {
      case (?admin) { if (not Principal.equal(msg.caller, admin)) return #err("Unauthorized") };
      case null { adminPrincipal := ?msg.caller };
    };
    apiKey := key;
    #ok()
  };

  public shared(msg) func setApiUrl(url : Text) : async Result.Result<(), Text> {
    switch (adminPrincipal) {
      case (?admin) { if (not Principal.equal(msg.caller, admin)) return #err("Unauthorized") };
      case null { adminPrincipal := ?msg.caller };
    };
    apiUrl := url;
    #ok()
  };

  public shared(msg) func summarizeTextPremium(content : Text) : async Result.Result<Text, Text> {
    if (Principal.isAnonymous(msg.caller)) return #err("Anonymous callers not allowed");
    if (isTooLargeForAI(content)) return #err("Document is too large for AI analysis");
    if (apiKey == "") return #err("API key not configured");

    let truncated = if (content.size() > 4000) {
      let chars = Text.toArray(content);
      Text.fromIter(Array.subArray(chars, 0, 4000).vals())
    } else { content };

    let requestBody = "{\"model\":\"claude-haiku-4-5-20251001\",\"max_tokens\":512,\"messages\":[{\"role\":\"user\",\"content\":\"Summarize the following document in 2-3 concise paragraphs. Focus on key points and main ideas:\\n\\n" # escapeJson(truncated) # "\"}]}";

    let requestHeaders : [HttpHeader] = [
      { name = "Content-Type"; value = "application/json" },
      { name = "x-api-key"; value = apiKey },
      { name = "anthropic-version"; value = "2023-06-01" },
    ];

    Cycles.add<system>(230_850_258_000);
    let httpResponse = await ic.http_request({
      url = apiUrl;
      max_response_bytes = ?Nat64.fromNat(10000);
      headers = requestHeaders;
      body = ?Text.encodeUtf8(requestBody);
      method = #post;
      transform = ?{ function = transform; context = Blob.fromArray([]) };
    });

    if (httpResponse.status != 200) {
      let errorBody = switch (Text.decodeUtf8(httpResponse.body)) { case (?t) t; case null "Unknown error" };
      return #err("API error (status " # Nat.toText(httpResponse.status) # "): " # errorBody);
    };

    switch (Text.decodeUtf8(httpResponse.body)) {
      case (?responseText) #ok(extractContentText(responseText));
      case null #err("Failed to decode response");
    };
  };

  // Keep backward compatibility
  public shared(_msg) func summarizeText(content : Text) : async Result.Result<Text, Text> {
    await summarizeOnChain(content)
  };

  func escapeJson(text : Text) : Text {
    var result = "";
    for (c in text.chars()) {
      if (c == '\"') { result #= "\\\"" }
      else if (c == '\\') { result #= "\\\\" }
      else if (c == '\n') { result #= "\\n" }
      else if (c == '\r') { result #= "\\r" }
      else if (c == '\t') { result #= "\\t" }
      else { result #= Char.toText(c) };
    };
    result
  };

  func extractContentText(json : Text) : Text {
    let chars = Text.toArray(json);
    let searchKey = "\"text\":\"";
    let searchChars = Text.toArray(searchKey);
    let searchLen = searchChars.size();
    var pos : Nat = 0;
    var found = false;
    label search while (pos + searchLen <= chars.size()) {
      var match = true;
      var j : Nat = 0;
      while (j < searchLen) {
        if (chars[pos + j] != searchChars[j]) { match := false; j := searchLen } else { j += 1 };
      };
      if (match) { found := true; break search };
      pos += 1;
    };
    if (not found) return json;
    var i = pos + searchLen;
    var result = "";
    var escaped = false;
    label reading while (i < chars.size()) {
      let c = chars[i];
      if (escaped) {
        if (c == 'n') { result #= "\n" } else if (c == 't') { result #= "\t" } else { result #= Char.toText(c) };
        escaped := false;
      } else if (c == '\\') { escaped := true }
      else if (c == '\"') { break reading }
      else { result #= Char.toText(c) };
      i += 1;
    };
    result
  };

  public query func health() : async Text {
    "DocuCollab AI Service running. On-chain AI: Enabled (icp_llm). Premium AI: " # (if (apiKey == "") "Not configured" else "Configured")
  };
};
