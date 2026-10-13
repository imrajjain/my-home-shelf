import { addToShelf } from "./shelf.js";

chrome.runtime.onInstalled.addListener((details) => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "page", title: "Add page to Shelf", contexts: ["page"] });
    chrome.contextMenus.create({ id: "link", title: "Add link to Shelf", contexts: ["link"] });
    chrome.contextMenus.create({ id: "selection", title: "Add “%s” to Shelf", contexts: ["selection"] });
    chrome.contextMenus.create({ id: "image", title: "Add image’s page to Shelf", contexts: ["image"] });
  });
  if (details.reason === "install") chrome.runtime.openOptionsPage();
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  let capture;
  switch (info.menuItemId) {
    case "link":
      capture = { url: info.linkUrl, title: info.selectionText };
      break;
    case "selection":
      // A selected phrase becomes something to explore; the page is kept as context.
      capture = { title: info.selectionText.slice(0, 140), selection: info.selectionText, note: tab?.url ? `From ${tab.url}` : undefined };
      if (/^https?:\/\/\S+$/.test(info.selectionText.trim())) capture = { url: info.selectionText.trim() };
      break;
    default:
      capture = { url: tab?.url, title: tab?.title };
  }
  await addAndAcknowledge(capture, tab);
});

chrome.commands.onCommand.addListener(async (command, tab) => {
  if (command !== "quick-add") return;
  tab ??= (await chrome.tabs.query({ active: true, currentWindow: true }))[0];
  if (!tab?.url?.startsWith("http")) return;
  const selection = await selectedText(tab.id);
  await addAndAcknowledge({ url: tab.url, title: tab.title, selection }, tab);
});

async function addAndAcknowledge(capture, tab) {
  const result = await addToShelf(capture);
  const tabId = tab?.id;
  if (tabId === undefined) return;
  if (result.ok) {
    await badge(tabId, "✓", "#5E8A6E");
  } else {
    await badge(tabId, "!", "#C2493F");
    if (result.error === "unpaired") chrome.runtime.openOptionsPage();
  }
}

async function badge(tabId, text, color) {
  await chrome.action.setBadgeBackgroundColor({ tabId, color });
  await chrome.action.setBadgeText({ tabId, text });
  setTimeout(() => chrome.action.setBadgeText({ tabId, text: "" }).catch(() => {}), 2200);
}

async function selectedText(tabId) {
  try {
    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => String(window.getSelection() || "").trim(),
    });
    return result || undefined;
  } catch {
    return undefined; // chrome:// pages, PDFs, etc.
  }
}
