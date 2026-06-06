import HashMap "mo:base/HashMap";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Nat32 "mo:base/Nat32";
import Nat8 "mo:base/Nat8";
import CertifiedData "mo:base/CertifiedData";
import Sha256 "mo:sha2/Sha256";

actor DocuCollab {

  // ===== TYPES =====

  public type DocumentId = Nat;
  public type ChunkId = Nat;

  public type DocumentMeta = {
    id : DocumentId;
    name : Text;
    mimeType : Text;
    size : Nat;
    owner : Principal;
    createdAt : Int;
    updatedAt : Int;
    isEncrypted : Bool;
    summary : ?Text;
    totalChunks : Nat;
    version : ?Nat;
    certifiedHash : ?Blob;
  };

  public type VersionInfo = {
    version : ?Nat;
    size : Nat;
    updatedAt : Int;
    totalChunks : Nat;
  };

  public type SharedAccess = {
    grantedTo : Principal;
    grantedBy : Principal;
    grantedAt : Int;
    expiresAt : ?Int;
    encryptedKey : Blob;
  };

  public type UserProfile = {
    principal : Principal;
    username : Text;
    publicKey : Blob;
    createdAt : Int;
  };

  public type DocumentWithAccess = {
    meta : DocumentMeta;
    accessList : [SharedAccess];
    isOwner : Bool;
  };

  public type ActivityAction = {
    #upload;
    #download;
    #share;
    #revoke;
    #delete;
    #summary;
  };

  public type ActivityEntry = {
    id : Nat;
    action : ActivityAction;
    performer : Principal;
    documentId : DocumentId;
    documentName : Text;
    targetUser : ?Principal;
    timestamp : Int;
  };

  // ===== STATE =====

  stable var nextDocId : Nat = 0;
  stable var nextActivityId : Nat = 0;
  stable var stableDocuments : [(DocumentId, DocumentMeta)] = [];
  stable var stableChunks : [(Text, Blob)] = [];
  stable var stableUsers : [(Principal, UserProfile)] = [];
  stable var stableAccess : [(Text, SharedAccess)] = [];
  stable var stableUserDocs : [(Principal, [DocumentId])] = [];
  stable var stableActivities : [ActivityEntry] = [];
  stable var stableVersions : [(DocumentId, [VersionInfo])] = [];

  var documents = HashMap.HashMap<DocumentId, DocumentMeta>(16, Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n % 2147483647) });
  var chunks = HashMap.HashMap<Text, Blob>(64, Text.equal, Text.hash);
  var users = HashMap.HashMap<Principal, UserProfile>(16, Principal.equal, Principal.hash);
  var access = HashMap.HashMap<Text, SharedAccess>(16, Text.equal, Text.hash);
  var userDocs = HashMap.HashMap<Principal, Buffer.Buffer<DocumentId>>(16, Principal.equal, Principal.hash);
  var activities = Buffer.Buffer<ActivityEntry>(32);
  var versionHistory = HashMap.HashMap<DocumentId, Buffer.Buffer<VersionInfo>>(16, Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n % 2147483647) });

  // ===== UPGRADE HOOKS =====

  system func preupgrade() {
    stableDocuments := Iter.toArray(documents.entries());
    stableChunks := Iter.toArray(chunks.entries());
    stableUsers := Iter.toArray(users.entries());
    stableAccess := Iter.toArray(access.entries());
    stableUserDocs := Array.map<(Principal, Buffer.Buffer<DocumentId>), (Principal, [DocumentId])>(
      Iter.toArray(userDocs.entries()),
      func(entry) { (entry.0, Buffer.toArray(entry.1)) }
    );
    stableActivities := Buffer.toArray(activities);
    stableVersions := Array.map<(DocumentId, Buffer.Buffer<VersionInfo>), (DocumentId, [VersionInfo])>(
      Iter.toArray(versionHistory.entries()),
      func(entry) { (entry.0, Buffer.toArray(entry.1)) }
    );
  };

  system func postupgrade() {
    for ((k, v) in stableDocuments.vals()) { documents.put(k, v) };
    for ((k, v) in stableChunks.vals()) { chunks.put(k, v) };
    for ((k, v) in stableUsers.vals()) { users.put(k, v) };
    for ((k, v) in stableAccess.vals()) { access.put(k, v) };
    for ((p, ids) in stableUserDocs.vals()) {
      let buf = Buffer.Buffer<DocumentId>(ids.size());
      for (id in ids.vals()) { buf.add(id) };
      userDocs.put(p, buf);
    };
    for (entry in stableActivities.vals()) { activities.add(entry) };
    for ((docId, versions) in stableVersions.vals()) {
      let buf = Buffer.Buffer<VersionInfo>(versions.size());
      for (v in versions.vals()) { buf.add(v) };
      versionHistory.put(docId, buf);
    };
    stableDocuments := [];
    stableChunks := [];
    stableUsers := [];
    stableAccess := [];
    stableUserDocs := [];
    stableActivities := [];
    stableVersions := [];
  };

  // ===== HELPERS =====

  func chunkKey(docId : DocumentId, chunkId : ChunkId) : Text {
    Nat.toText(docId) # "-" # Nat.toText(chunkId)
  };

  func accessKey(docId : DocumentId, p : Principal) : Text {
    Nat.toText(docId) # "-" # Principal.toText(p)
  };

  func getUserDocs(p : Principal) : Buffer.Buffer<DocumentId> {
    switch (userDocs.get(p)) {
      case (?buf) buf;
      case null {
        let buf = Buffer.Buffer<DocumentId>(4);
        userDocs.put(p, buf);
        buf;
      };
    };
  };

  func getVersion(v : ?Nat) : Nat {
    switch (v) { case (?n) n; case null 1 };
  };

  func logActivity(action : ActivityAction, who : Principal, docId : DocumentId, docName : Text, target : ?Principal) {
    let entry : ActivityEntry = {
      id = nextActivityId;
      action = action;
      performer = who;
      documentId = docId;
      documentName = docName;
      targetUser = target;
      timestamp = Time.now();
    };
    nextActivityId += 1;
    activities.add(entry);
  };

  func hasAccess(docId : DocumentId, caller : Principal) : Bool {
    switch (documents.get(docId)) {
      case (?doc) {
        if (Principal.equal(doc.owner, caller)) return true;
        switch (access.get(accessKey(docId, caller))) {
          case (?a) {
            switch (a.expiresAt) {
              case (?exp) { exp > Time.now() };
              case null true;
            };
          };
          case null false;
        };
      };
      case null false;
    };
  };

  // ===== USER MANAGEMENT =====

  public shared(msg) func registerUser(username : Text, publicKey : Blob) : async Result.Result<UserProfile, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot register");
    };
    let profile : UserProfile = {
      principal = caller;
      username = username;
      publicKey = publicKey;
      createdAt = Time.now();
    };
    users.put(caller, profile);
    #ok(profile)
  };

  public query(msg) func getMyProfile() : async ?UserProfile {
    users.get(msg.caller)
  };

  public query func getUser(p : Principal) : async ?UserProfile {
    users.get(p)
  };

  public query func getUserByName(name : Text) : async ?UserProfile {
    for ((_, profile) in users.entries()) {
      if (profile.username == name) return ?profile;
    };
    null
  };

  public shared(msg) func whoAmI() : async Principal {
    msg.caller
  };

  // ===== DOCUMENT UPLOAD =====

  public shared(msg) func createDocument(name : Text, mimeType : Text, size : Nat, totalChunks : Nat, isEncrypted : Bool) : async Result.Result<DocumentId, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) {
      return #err("Anonymous users cannot create documents");
    };
    let docId = nextDocId;
    nextDocId += 1;
    let now = Time.now();
    let meta : DocumentMeta = {
      id = docId;
      name = name;
      mimeType = mimeType;
      size = size;
      owner = caller;
      createdAt = now;
      updatedAt = now;
      isEncrypted = isEncrypted;
      summary = null;
      totalChunks = totalChunks;
      version = ?1;
      certifiedHash = null;
    };
    documents.put(docId, meta);
    getUserDocs(caller).add(docId);
    logActivity(#upload, caller, docId, name, null);
    #ok(docId)
  };

  public shared(msg) func uploadChunk(docId : DocumentId, chunkId : ChunkId, data : Blob) : async Result.Result<(), Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can upload chunks");
        };
        if (chunkId >= doc.totalChunks) {
          return #err("Chunk ID exceeds total chunks");
        };
        chunks.put(chunkKey(docId, chunkId), data);
        let updated : DocumentMeta = {
          id = doc.id;
          name = doc.name;
          mimeType = doc.mimeType;
          size = doc.size;
          owner = doc.owner;
          createdAt = doc.createdAt;
          updatedAt = Time.now();
          isEncrypted = doc.isEncrypted;
          summary = doc.summary;
          totalChunks = doc.totalChunks;
          version = doc.version;
          certifiedHash = doc.certifiedHash;
        };
        documents.put(docId, updated);
        #ok()
      };
      case null #err("Document not found");
    };
  };

  // ===== DOCUMENT DOWNLOAD =====

  public query(msg) func downloadChunk(docId : DocumentId, chunkId : ChunkId) : async Result.Result<Blob, Text> {
    let caller = msg.caller;
    if (not hasAccess(docId, caller)) {
      return #err("Access denied");
    };
    switch (chunks.get(chunkKey(docId, chunkId))) {
      case (?data) #ok(data);
      case null #err("Chunk not found");
    };
  };

  // ===== DOCUMENT MANAGEMENT =====

  public query(msg) func getMyDocuments() : async [DocumentMeta] {
    let caller = msg.caller;
    switch (userDocs.get(caller)) {
      case (?buf) {
        let result = Buffer.Buffer<DocumentMeta>(buf.size());
        for (docId in buf.vals()) {
          switch (documents.get(docId)) {
            case (?doc) result.add(doc);
            case null {};
          };
        };
        Buffer.toArray(result)
      };
      case null [];
    };
  };

  public query(msg) func getSharedWithMe() : async [DocumentWithAccess] {
    let caller = msg.caller;
    let result = Buffer.Buffer<DocumentWithAccess>(4);
    for ((key, acc) in access.entries()) {
      if (Principal.equal(acc.grantedTo, caller)) {
        let valid = switch (acc.expiresAt) {
          case (?exp) { exp > Time.now() };
          case null true;
        };
        if (valid) {
          let parts = Text.split(key, #char '-');
          let partsArray = Iter.toArray(parts);
          if (partsArray.size() > 0) {
            for ((docId, doc) in documents.entries()) {
              if (Nat.toText(docId) == partsArray[0]) {
                result.add({
                  meta = doc;
                  accessList = [acc];
                  isOwner = false;
                });
              };
            };
          };
        };
      };
    };
    Buffer.toArray(result)
  };

  public query(msg) func getDocument(docId : DocumentId) : async Result.Result<DocumentWithAccess, Text> {
    let caller = msg.caller;
    if (not hasAccess(docId, caller)) {
      return #err("Access denied");
    };
    switch (documents.get(docId)) {
      case (?doc) {
        let accessList = Buffer.Buffer<SharedAccess>(4);
        if (Principal.equal(doc.owner, caller)) {
          for ((key, acc) in access.entries()) {
            if (Text.startsWith(key, #text(Nat.toText(docId) # "-"))) {
              accessList.add(acc);
            };
          };
        };
        #ok({
          meta = doc;
          accessList = Buffer.toArray(accessList);
          isOwner = Principal.equal(doc.owner, caller);
        })
      };
      case null #err("Document not found");
    };
  };

  public shared(msg) func deleteDocument(docId : DocumentId) : async Result.Result<(), Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can delete documents");
        };
        var i : Nat = 0;
        while (i < doc.totalChunks) {
          chunks.delete(chunkKey(docId, i));
          i += 1;
        };
        let keysToRemove = Buffer.Buffer<Text>(4);
        for ((key, _) in access.entries()) {
          if (Text.startsWith(key, #text(Nat.toText(docId) # "-"))) {
            keysToRemove.add(key);
          };
        };
        for (key in keysToRemove.vals()) {
          access.delete(key);
        };
        switch (userDocs.get(caller)) {
          case (?buf) {
            let newBuf = Buffer.Buffer<DocumentId>(buf.size());
            for (id in buf.vals()) {
              if (id != docId) newBuf.add(id);
            };
            userDocs.put(caller, newBuf);
          };
          case null {};
        };
        logActivity(#delete, caller, docId, doc.name, null);
        documents.delete(docId);
        #ok()
      };
      case null #err("Document not found");
    };
  };

  // ===== SHARING =====

  public shared(msg) func shareDocument(docId : DocumentId, grantTo : Principal, encryptedKey : Blob, expiresAt : ?Int) : async Result.Result<(), Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can share documents");
        };
        let sharedAccess : SharedAccess = {
          grantedTo = grantTo;
          grantedBy = caller;
          grantedAt = Time.now();
          expiresAt = expiresAt;
          encryptedKey = encryptedKey;
        };
        access.put(accessKey(docId, grantTo), sharedAccess);
        getUserDocs(grantTo).add(docId);
        logActivity(#share, caller, docId, doc.name, ?grantTo);
        #ok()
      };
      case null #err("Document not found");
    };
  };

  public shared(msg) func revokeAccess(docId : DocumentId, revokeFrom : Principal) : async Result.Result<(), Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can revoke access");
        };
        access.delete(accessKey(docId, revokeFrom));
        logActivity(#revoke, caller, docId, doc.name, ?revokeFrom);
        switch (userDocs.get(revokeFrom)) {
          case (?buf) {
            let newBuf = Buffer.Buffer<DocumentId>(buf.size());
            for (id in buf.vals()) {
              if (id != docId) newBuf.add(id);
            };
            userDocs.put(revokeFrom, newBuf);
          };
          case null {};
        };
        #ok()
      };
      case null #err("Document not found");
    };
  };

  // ===== AI SUMMARY =====

  public shared(msg) func setSummary(docId : DocumentId, summary : Text) : async Result.Result<(), Text> {
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, msg.caller)) {
          return #err("Only the owner can set summary");
        };
        let updated : DocumentMeta = {
          id = doc.id;
          name = doc.name;
          mimeType = doc.mimeType;
          size = doc.size;
          owner = doc.owner;
          createdAt = doc.createdAt;
          updatedAt = Time.now();
          isEncrypted = doc.isEncrypted;
          summary = ?summary;
          totalChunks = doc.totalChunks;
          version = doc.version;
          certifiedHash = doc.certifiedHash;
        };
        documents.put(docId, updated);
        logActivity(#summary, msg.caller, docId, doc.name, null);
        #ok()
      };
      case null #err("Document not found");
    };
  };

  // ===== VERSIONING =====

  public shared(msg) func uploadNewVersion(docId : DocumentId, size : Nat, totalChunks : Nat) : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can upload new versions");
        };
        // Save current version to history
        let vInfo : VersionInfo = {
          version = doc.version;
          size = doc.size;
          updatedAt = doc.updatedAt;
          totalChunks = doc.totalChunks;
        };
        let hist = switch (versionHistory.get(docId)) {
          case (?buf) buf;
          case null {
            let buf = Buffer.Buffer<VersionInfo>(4);
            versionHistory.put(docId, buf);
            buf;
          };
        };
        hist.add(vInfo);
        // Update document with new version
        let curVer = getVersion(doc.version);
        let newVersion = curVer + 1;
        let now = Time.now();
        let updated : DocumentMeta = {
          id = doc.id;
          name = doc.name;
          mimeType = doc.mimeType;
          size = size;
          owner = doc.owner;
          createdAt = doc.createdAt;
          updatedAt = now;
          isEncrypted = doc.isEncrypted;
          summary = doc.summary;
          totalChunks = totalChunks;
          version = ?newVersion;
          certifiedHash = null;
        };
        // Clear old chunks
        var i : Nat = 0;
        while (i < doc.totalChunks) {
          chunks.delete(chunkKey(docId, i));
          i += 1;
        };
        documents.put(docId, updated);
        logActivity(#upload, caller, docId, doc.name, null);
        #ok(newVersion)
      };
      case null #err("Document not found");
    };
  };

  public query func getVersions(docId : DocumentId) : async [VersionInfo] {
    switch (versionHistory.get(docId)) {
      case (?buf) Buffer.toArray(buf);
      case null [];
    };
  };

  // ===== DOCUMENT INTEGRITY (Certified Data) =====

  func computeDocHash(docId : DocumentId, totalChunks : Nat) : Blob {
    let digest = Sha256.Digest(#sha256);
    var i : Nat = 0;
    while (i < totalChunks) {
      switch (chunks.get(chunkKey(docId, i))) {
        case (?data) { digest.writeIter(data.vals()) };
        case null {};
      };
      i += 1;
    };
    digest.sum()
  };

  public shared(msg) func finalizeDocument(docId : DocumentId) : async Result.Result<Blob, Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can finalize documents");
        };
        let hash = computeDocHash(docId, doc.totalChunks);
        CertifiedData.set(hash);
        let updated : DocumentMeta = {
          id = doc.id;
          name = doc.name;
          mimeType = doc.mimeType;
          size = doc.size;
          owner = doc.owner;
          createdAt = doc.createdAt;
          updatedAt = doc.updatedAt;
          isEncrypted = doc.isEncrypted;
          summary = doc.summary;
          totalChunks = doc.totalChunks;
          version = doc.version;
          certifiedHash = ?hash;
        };
        documents.put(docId, updated);
        #ok(hash)
      };
      case null #err("Document not found");
    };
  };

  public query func getDocumentHash(docId : DocumentId) : async Result.Result<{ hash : Blob; certificate : ?Blob }, Text> {
    switch (documents.get(docId)) {
      case (?doc) {
        switch (doc.certifiedHash) {
          case (?hash) {
            #ok({ hash = hash; certificate = CertifiedData.getCertificate() })
          };
          case null #err("Document not yet finalized");
        };
      };
      case null #err("Document not found");
    };
  };

  func blobToHex(b : Blob) : Text {
    let hexChars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
    var result = "";
    for (byte in b.vals()) {
      result #= hexChars[Nat8.toNat(byte / 16)];
      result #= hexChars[Nat8.toNat(byte % 16)];
    };
    result
  };

  public query func getDocumentHashHex(docId : DocumentId) : async Result.Result<Text, Text> {
    switch (documents.get(docId)) {
      case (?doc) {
        switch (doc.certifiedHash) {
          case (?hash) #ok(blobToHex(hash));
          case null #err("Document not yet finalized");
        };
      };
      case null #err("Document not found");
    };
  };

  // ===== ACTIVITY LOG =====

  public query(msg) func getActivities(limit : Nat) : async [ActivityEntry] {
    let caller = msg.caller;
    let size = activities.size();
    if (size == 0) return [];
    let cap = if (limit == 0 or limit > size) { size } else { limit };
    let result = Buffer.Buffer<ActivityEntry>(cap);
    var count : Nat = 0;
    var idx : Nat = size;
    label l while (idx > 0 and count < cap) {
      idx -= 1;
      let entry = activities.get(idx);
      if (Principal.equal(entry.performer, caller)) {
        result.add(entry);
        count += 1;
      };
    };
    Buffer.toArray(result)
  };

  public query func getAllActivities(limit : Nat) : async [ActivityEntry] {
    let size = activities.size();
    if (size == 0) return [];
    let cap = if (limit == 0 or limit > size) { size } else { limit };
    let result = Buffer.Buffer<ActivityEntry>(cap);
    var idx : Nat = size;
    var count : Nat = 0;
    while (idx > 0 and count < cap) {
      idx -= 1;
      result.add(activities.get(idx));
      count += 1;
    };
    Buffer.toArray(result)
  };

  // ===== STATS =====

  public query func getStats() : async { totalDocuments : Nat; totalUsers : Nat; totalStorage : Nat } {
    var totalStorage : Nat = 0;
    for ((_, doc) in documents.entries()) {
      totalStorage += doc.size;
    };
    {
      totalDocuments = documents.size();
      totalUsers = users.size();
      totalStorage = totalStorage;
    }
  };

  public query(msg) func getMyStorageUsed() : async Nat {
    let caller = msg.caller;
    var total : Nat = 0;
    switch (userDocs.get(caller)) {
      case (?buf) {
        for (docId in buf.vals()) {
          switch (documents.get(docId)) {
            case (?doc) {
              if (Principal.equal(doc.owner, caller)) {
                total += doc.size;
              };
            };
            case null {};
          };
        };
      };
      case null {};
    };
    total
  };
};
