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

  public type EncryptedSummary = {
    docId : DocumentId;
    ciphertext : Blob;
    iv : Blob;
    updatedAt : Int;
  };

  public type VersionInfo = {
    version : ?Nat;
    size : Nat;
    updatedAt : Int;
    totalChunks : Nat;
  };

  type PendingVersion = {
    version : Nat;
    size : Nat;
    totalChunks : Nat;
    startedAt : Int;
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
  stable var stableEncryptedSummaries : [(DocumentId, EncryptedSummary)] = [];
  stable var stablePendingVersions : [(DocumentId, PendingVersion)] = [];
  stable var stableOwnerKeys : [(DocumentId, Blob)] = [];
  stable var adminPrincipal : ?Principal = null;

  var documents = HashMap.HashMap<DocumentId, DocumentMeta>(16, Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n % 2147483647) });
  var chunks = HashMap.HashMap<Text, Blob>(64, Text.equal, Text.hash);
  var users = HashMap.HashMap<Principal, UserProfile>(16, Principal.equal, Principal.hash);
  var access = HashMap.HashMap<Text, SharedAccess>(16, Text.equal, Text.hash);
  var userDocs = HashMap.HashMap<Principal, Buffer.Buffer<DocumentId>>(16, Principal.equal, Principal.hash);
  var activities = Buffer.Buffer<ActivityEntry>(32);
  var versionHistory = HashMap.HashMap<DocumentId, Buffer.Buffer<VersionInfo>>(16, Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n % 2147483647) });
  var encryptedSummaries = HashMap.HashMap<DocumentId, EncryptedSummary>(16, Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n % 2147483647) });
  var pendingVersions = HashMap.HashMap<DocumentId, PendingVersion>(16, Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n % 2147483647) });
  var ownerWrappedKeys = HashMap.HashMap<DocumentId, Blob>(16, Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n % 2147483647) });

  let BOOTSTRAP_ADMIN : Principal = Principal.fromText("hitz2-x2re7-nstm2-xmor4-yafac-enmkh-z7r2d-odjug-wlstk-mmaj3-7qe");
  let MAX_DOCUMENT_SIZE : Nat = 50 * 1024 * 1024;
  let MAX_CHUNK_SIZE : Nat = 1_100_000;
  let MAX_CHUNKS : Nat = 64;
  let MAX_USERNAME_LENGTH : Nat = 32;

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
    stableEncryptedSummaries := Iter.toArray(encryptedSummaries.entries());
    stablePendingVersions := Iter.toArray(pendingVersions.entries());
    stableOwnerKeys := Iter.toArray(ownerWrappedKeys.entries());
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
    for ((k, v) in stableEncryptedSummaries.vals()) { encryptedSummaries.put(k, v) };
    for ((k, v) in stablePendingVersions.vals()) { pendingVersions.put(k, v) };
    for ((k, v) in stableOwnerKeys.vals()) { ownerWrappedKeys.put(k, v) };
    stableDocuments := [];
    stableChunks := [];
    stableUsers := [];
    stableAccess := [];
    stableUserDocs := [];
    stableActivities := [];
    stableVersions := [];
    stableEncryptedSummaries := [];
    stablePendingVersions := [];
    stableOwnerKeys := [];
  };

  // ===== HELPERS =====

  func chunkKey(docId : DocumentId, chunkId : ChunkId) : Text {
    Nat.toText(docId) # "-" # Nat.toText(chunkId)
  };

  func pendingChunkKey(docId : DocumentId, chunkId : ChunkId) : Text {
    "pending-" # Nat.toText(docId) # "-" # Nat.toText(chunkId)
  };

  func deletePendingVersionChunks(docId : DocumentId, pending : PendingVersion) {
    var i : Nat = 0;
    while (i < pending.totalChunks) {
      chunks.delete(pendingChunkKey(docId, i));
      i += 1;
    };
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

  func removeDocFromUserDocs(p : Principal, docId : DocumentId) {
    switch (userDocs.get(p)) {
      case (?buf) {
        let newBuf = Buffer.Buffer<DocumentId>(buf.size());
        for (id in buf.vals()) {
          if (id != docId) newBuf.add(id);
        };
        userDocs.put(p, newBuf);
      };
      case null {};
    };
  };

  func removeDocFromAllUserDocs(docId : DocumentId) {
    let principals = Buffer.Buffer<Principal>(userDocs.size());
    for ((p, _) in userDocs.entries()) {
      principals.add(p);
    };
    for (p in principals.vals()) {
      removeDocFromUserDocs(p, docId);
    };
  };

  func hasRegisteredPublicKey(p : Principal) : Bool {
    switch (users.get(p)) {
      case (?profile) profile.publicKey.size() > 0;
      case null false;
    };
  };

  func addVersionHistory(docId : DocumentId, doc : DocumentMeta) {
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
  };

  func computeDocHash(docId : DocumentId, totalChunks : Nat, staged : Bool) : ?Blob {
    let digest = Sha256.Digest(#sha256);
    var i : Nat = 0;
    while (i < totalChunks) {
      let key = if (staged) { pendingChunkKey(docId, i) } else { chunkKey(docId, i) };
      switch (chunks.get(key)) {
        case (?data) { digest.writeIter(data.vals()) };
        case null { return null };
      };
      i += 1;
    };
    ?digest.sum()
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
    if (username.size() == 0 or username.size() > MAX_USERNAME_LENGTH) {
      return #err("Username must be between 1 and 32 characters");
    };
    switch (users.get(caller)) {
      case (?_) { return #err("User already registered") };
      case null {};
    };
    for ((p, profile) in users.entries()) {
      if (profile.username == username and not Principal.equal(p, caller)) {
        return #err("Username is already taken");
      };
    };
    switch (adminPrincipal) {
      case null {
        if (Principal.equal(caller, BOOTSTRAP_ADMIN)) {
          adminPrincipal := ?caller;
        };
      };
      case (?_) {};
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
    switch (users.get(caller)) {
      case null { return #err("Only registered users can create documents") };
      case (?_) {};
    };
    if (name.size() == 0) {
      return #err("Document name is required");
    };
    if (size == 0 or size > MAX_DOCUMENT_SIZE) {
      return #err("Document size must be between 1 byte and 50 MB");
    };
    if (totalChunks == 0 or totalChunks > MAX_CHUNKS) {
      return #err("Document chunk count is outside the supported MVP range");
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
        if (data.size() == 0 or data.size() > MAX_CHUNK_SIZE) {
          return #err("Chunk size is outside the supported MVP range");
        };
        switch (pendingVersions.get(docId)) {
          case (?pending) {
            if (chunkId >= pending.totalChunks) {
              return #err("Chunk ID exceeds pending version chunk count");
            };
            chunks.put(pendingChunkKey(docId, chunkId), data);
            #ok()
          };
          case null {
            if (chunkId >= doc.totalChunks) {
              return #err("Chunk ID exceeds total chunks");
            };
            switch (doc.certifiedHash) {
              case (?_) { return #err("Document is finalized; start a new version before replacing chunks") };
              case null {};
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
              certifiedHash = null;
            };
            documents.put(docId, updated);
            #ok()
          };
        }
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
            case (?doc) {
              if (Principal.equal(doc.owner, caller)) {
                result.add(doc);
              };
            };
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
        } else {
          switch (access.get(accessKey(docId, caller))) {
            case (?acc) {
              let valid = switch (acc.expiresAt) {
                case (?exp) { exp > Time.now() };
                case null true;
              };
              if (valid) {
                accessList.add(acc);
              };
            };
            case null {};
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
        switch (pendingVersions.get(docId)) {
          case (?pending) {
            deletePendingVersionChunks(docId, pending);
            pendingVersions.delete(docId);
          };
          case null {};
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
        removeDocFromAllUserDocs(docId);
        logActivity(#delete, caller, docId, doc.name, null);
        encryptedSummaries.delete(docId);
        ownerWrappedKeys.delete(docId);
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
        if (Principal.equal(doc.owner, grantTo)) {
          return #err("Cannot share a document with its owner");
        };
        if (doc.isEncrypted and encryptedKey.size() == 0) {
          return #err("Encrypted documents require a wrapped document key for the recipient");
        };
        if (doc.isEncrypted and not hasRegisteredPublicKey(grantTo)) {
          return #err("Encrypted documents can only be shared with registered users that have a public key");
        };
        let sharedAccess : SharedAccess = {
          grantedTo = grantTo;
          grantedBy = caller;
          grantedAt = Time.now();
          expiresAt = expiresAt;
          encryptedKey = encryptedKey;
        };
        let alreadyShared = switch (access.get(accessKey(docId, grantTo))) {
          case (?_) true;
          case null false;
        };
        access.put(accessKey(docId, grantTo), sharedAccess);
        if (not alreadyShared) {
          getUserDocs(grantTo).add(docId);
        };
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
        removeDocFromUserDocs(revokeFrom, docId);
        #ok()
      };
      case null #err("Document not found");
    };
  };

  // ===== OWNER WRAPPED KEY (for cross-browser recovery) =====

  public shared(msg) func setOwnerWrappedKey(docId : DocumentId, wrappedKey : Blob) : async Result.Result<(), Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can set the owner wrapped key");
        };
        if (wrappedKey.size() == 0) {
          return #err("Wrapped key cannot be empty");
        };
        if (wrappedKey.size() > 512) {
          return #err("Wrapped key is too large (max 512 bytes for RSA-2048 wrapped AES key)");
        };
        ownerWrappedKeys.put(docId, wrappedKey);
        #ok()
      };
      case null #err("Document not found");
    };
  };

  public query(msg) func getOwnerWrappedKey(docId : DocumentId) : async Result.Result<Blob, Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can retrieve the owner wrapped key");
        };
        switch (ownerWrappedKeys.get(docId)) {
          case (?key) #ok(key);
          case null #err("No owner wrapped key found");
        };
      };
      case null #err("Document not found");
    };
  };

  // ===== AI SUMMARY =====

  public shared(msg) func setSummary(docId : DocumentId, _summary : Text) : async Result.Result<(), Text> {
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, msg.caller)) {
          return #err("Only the owner can set summary");
        };
        #err("Plaintext summaries are deprecated; use setEncryptedSummary")
      };
      case null #err("Document not found");
    };
  };

  public shared(msg) func setEncryptedSummary(docId : DocumentId, ciphertext : Blob, iv : Blob) : async Result.Result<(), Text> {
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, msg.caller)) {
          return #err("Only the owner can set summary");
        };
        if (ciphertext.size() == 0 or iv.size() == 0) {
          return #err("Encrypted summary payload is required");
        };
        let now = Time.now();
        let summary : EncryptedSummary = {
          docId = docId;
          ciphertext = ciphertext;
          iv = iv;
          updatedAt = now;
        };
        let updated : DocumentMeta = {
          id = doc.id;
          name = doc.name;
          mimeType = doc.mimeType;
          size = doc.size;
          owner = doc.owner;
          createdAt = doc.createdAt;
          updatedAt = now;
          isEncrypted = doc.isEncrypted;
          summary = null;
          totalChunks = doc.totalChunks;
          version = doc.version;
          certifiedHash = doc.certifiedHash;
        };
        encryptedSummaries.put(docId, summary);
        documents.put(docId, updated);
        logActivity(#summary, msg.caller, docId, doc.name, null);
        #ok()
      };
      case null #err("Document not found");
    };
  };

  public query(msg) func getEncryptedSummary(docId : DocumentId) : async Result.Result<EncryptedSummary, Text> {
    if (not hasAccess(docId, msg.caller)) {
      return #err("Access denied");
    };
    switch (encryptedSummaries.get(docId)) {
      case (?summary) #ok(summary);
      case null #err("Summary not found");
    };
  };

  // ===== VERSIONING =====

  public shared(msg) func uploadNewVersion(docId : DocumentId, size : Nat, totalChunks : Nat) : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) { return #err("Anonymous users cannot upload versions") };
    switch (users.get(caller)) {
      case null { return #err("Only registered users can upload versions") };
      case (?_) {};
    };
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can upload new versions");
        };
        if (size == 0 or size > MAX_DOCUMENT_SIZE) {
          return #err("Document size must be between 1 byte and 50 MB");
        };
        if (totalChunks == 0 or totalChunks > MAX_CHUNKS) {
          return #err("Document chunk count is outside the supported MVP range");
        };
        switch (pendingVersions.get(docId)) {
          case (?oldPending) {
            deletePendingVersionChunks(docId, oldPending);
          };
          case null {};
        };
        let curVer = getVersion(doc.version);
        let newVersion = curVer + 1;
        let pending : PendingVersion = {
          version = newVersion;
          size = size;
          totalChunks = totalChunks;
          startedAt = Time.now();
        };
        pendingVersions.put(docId, pending);
        #ok(newVersion)
      };
      case null #err("Document not found");
    };
  };

  public shared(msg) func cancelPendingVersion(docId : DocumentId) : async Result.Result<(), Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can cancel pending versions");
        };
        switch (pendingVersions.get(docId)) {
          case (?pending) {
            deletePendingVersionChunks(docId, pending);
            pendingVersions.delete(docId);
          };
          case null {};
        };
        #ok()
      };
      case null #err("Document not found");
    };
  };

  public query(msg) func getVersions(docId : DocumentId) : async [VersionInfo] {
    if (not hasAccess(docId, msg.caller)) {
      return [];
    };
    switch (versionHistory.get(docId)) {
      case (?buf) Buffer.toArray(buf);
      case null [];
    };
  };

  // ===== DOCUMENT INTEGRITY =====

  public shared(msg) func finalizeDocument(docId : DocumentId) : async Result.Result<Blob, Text> {
    let caller = msg.caller;
    switch (documents.get(docId)) {
      case (?doc) {
        if (not Principal.equal(doc.owner, caller)) {
          return #err("Only the owner can finalize documents");
        };
        switch (pendingVersions.get(docId)) {
          case (?pending) {
            switch (computeDocHash(docId, pending.totalChunks, true)) {
              case (?hash) {
                addVersionHistory(docId, doc);
                var oldIndex : Nat = 0;
                while (oldIndex < doc.totalChunks) {
                  chunks.delete(chunkKey(docId, oldIndex));
                  oldIndex += 1;
                };
                var newIndex : Nat = 0;
                while (newIndex < pending.totalChunks) {
                  switch (chunks.get(pendingChunkKey(docId, newIndex))) {
                    case (?data) {
                      chunks.put(chunkKey(docId, newIndex), data);
                      chunks.delete(pendingChunkKey(docId, newIndex));
                    };
                    case null {};
                  };
                  newIndex += 1;
                };
                encryptedSummaries.delete(docId);
                let updated : DocumentMeta = {
                  id = doc.id;
                  name = doc.name;
                  mimeType = doc.mimeType;
                  size = pending.size;
                  owner = doc.owner;
                  createdAt = doc.createdAt;
                  updatedAt = Time.now();
                  isEncrypted = doc.isEncrypted;
                  summary = null;
                  totalChunks = pending.totalChunks;
                  version = ?pending.version;
                  certifiedHash = ?hash;
                };
                documents.put(docId, updated);
                pendingVersions.delete(docId);
                CertifiedData.set(hash);
                logActivity(#upload, caller, docId, doc.name, null);
                #ok(hash)
              };
              case null #err("Cannot finalize: pending version is missing one or more chunks");
            }
          };
          case null {
            switch (computeDocHash(docId, doc.totalChunks, false)) {
              case (?hash) {
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
              case null #err("Cannot finalize: document is missing one or more chunks");
            }
          };
        }
      };
      case null #err("Document not found");
    };
  };

  public query(msg) func getDocumentHash(docId : DocumentId) : async Result.Result<{ hash : Blob; certificate : ?Blob }, Text> {
    if (not hasAccess(docId, msg.caller)) {
      return #err("Access denied");
    };
    switch (documents.get(docId)) {
      case (?doc) {
        switch (doc.certifiedHash) {
          case (?hash) {
            #ok({ hash = hash; certificate = null })
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

  public query(msg) func getDocumentHashHex(docId : DocumentId) : async Result.Result<Text, Text> {
    if (not hasAccess(docId, msg.caller)) {
      return #err("Access denied");
    };
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

  public query(msg) func getAllActivities(limit : Nat) : async [ActivityEntry] {
    let isAdminCaller = switch (adminPrincipal) {
      case (?admin) Principal.equal(msg.caller, admin);
      case null Principal.equal(msg.caller, BOOTSTRAP_ADMIN);
    };
    if (not isAdminCaller) return [];
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
