import { AuthClient } from "@dfinity/auth-client";
import { HttpAgent } from "@dfinity/agent";
import { createActor as createBackendActor, canisterId as backendCanisterId } from "declarations/docucollab_backend";
import { createActor as createAiActor, canisterId as aiCanisterId } from "declarations/docucollab_ai";
import { clearKeyScope, setKeyScope } from "./crypto";

let authClient = null;
let backendActor = null;
let aiActor = null;

function getIdentityProvider() {
  return "https://id.ai";
}

function getReplicaHost() {
  if (process.env.DFX_NETWORK === "ic") {
    return "https://icp-api.io";
  }
  return "http://127.0.0.1:8080";
}

export async function initAuth() {
  authClient = await AuthClient.create({
    idleOptions: {
      idleTimeout: 1000 * 60 * 60 * 24,
      disableDefaultIdleCallback: true,
    },
  });
  if (await authClient.isAuthenticated()) {
    await setupActors();
  }
  return authClient;
}

async function setupActors() {
  const identity = authClient.getIdentity();
  setKeyScope(identity.getPrincipal().toText());
  const host = getReplicaHost();
  const agent = await HttpAgent.create({ identity, host });

  if (process.env.DFX_NETWORK !== "ic") {
    await agent.fetchRootKey();
  }

  backendActor = createBackendActor(backendCanisterId, { agent });
  aiActor = createAiActor(aiCanisterId, { agent });
}

export async function login() {
  const identityProvider = getIdentityProvider();

  return new Promise((resolve, reject) => {
    authClient.login({
      identityProvider,
      maxTimeToLive: BigInt(7 * 24 * 60 * 60 * 1000_000_000),
      onSuccess: async () => {
        await setupActors();
        resolve(true);
      },
      onError: (err) => {
        console.error("Login error:", err);
        reject(err);
      },
    });
  });
}

export async function logout() {
  await authClient.logout();
  backendActor = null;
  aiActor = null;
  clearKeyScope();
}

export function isAuthenticated() {
  return authClient?.isAuthenticated() ?? false;
}

export function getBackend() {
  return backendActor;
}

export function getAI() {
  return aiActor;
}

export function getPrincipal() {
  return authClient?.getIdentity()?.getPrincipal();
}
