import { writable } from "svelte/store";

export const isAuthenticated = writable(false);
export const userProfile = writable(null);
export const documents = writable([]);
export const sharedDocuments = writable([]);
export const currentDocument = writable(null);
export const isLoading = writable(false);
export const notification = writable(null);
export const darkMode = writable(false);

export function notify(message, type = "info") {
  notification.set({ message, type });
  setTimeout(() => notification.set(null), 4000);
}
