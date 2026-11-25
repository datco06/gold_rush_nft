"use strict";
const $ = (id) => document.getElementById(id);
let csrf = "";

function showLogin() {
  csrf = "";
  $("dashboard").hidden = true;
  $("login-panel").hidden = false;
  $("codes").replaceChildren();
  $("new-code").value = "";
  $("qr-image").removeAttribute("src");
  $("download-qr").removeAttribute("href");
  $("preview-result").hidden = true;
  $("preview-empty").hidden = false;
}

async function api(path, body) {
  const response = await fetch(`/api/admin/${path}`, {
    method: body === undefined ? "GET" : "POST",
    credentials: "same-origin",
    headers: {"Content-Type": "application/json", "X-Admin-Request": "1", "X-CSRF-Token": csrf},
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const data = await response.json();
  if (!response.ok) {
    if (response.status === 401 && path !== "login") showLogin();
    const message = typeof data.detail === "string" ? data.detail :
      response.status === 422 ? "Thông tin chưa hợp lệ. Kiểm tra số lượng, token ID và hạn dùng." : "Không xử lý được yêu cầu. Vui lòng thử lại.";
    throw new Error(message);
  }
  return data;
}

function errorMessage(error) {
  return error instanceof TypeError ? "Không kết nối được máy chủ. Kiểm tra kết nối rồi thử lại." : error.message;
}

async function busy(button, work) {
  button.disabled = true;
  const label = button.textContent;
  button.textContent = "Đang xử lý…";
  try { await work(); } finally { button.disabled = false; button.textContent = label; }
}

function text(tag, content, className) {
  const element = document.createElement(tag);
  element.textContent = content;
  if (className) element.className = className;
  return element;
}

async function refresh() {
  $("list-error").textContent = "";
  try {
    const data = await api("codes");
    for (const name of ["total", "used", "locked"]) $(name).textContent = data.summary[name].toLocaleString("vi-VN");
    const rows = data.codes.map((code) => {
      const row = document.createElement("article"); row.className = "code-row";
      const details = document.createElement("div");
      const reward = code.reward_type === "gold" ? `${code.amount} vàng` : `${code.amount} vật phẩm · Token #${code.token_id}`;
      const expired = code.expires_at !== null && code.expires_at * 1000 <= Date.now();
      const state = !code.active ? "Đang khóa" : expired ? "Hết hạn" : code.used_count >= code.max_uses ? "Hết lượt" : "Đang mở";
      details.append(text("h3", code.name), text("p", `${reward} · ${code.used_count}/${code.max_uses} lượt đã dùng / giữ chỗ`), text("span", state, "badge"));
      details.append(text("p", `ID: ${code.code_hash.slice(0, 12)}… · ${code.expires_at ? "Hạn: " + new Date(code.expires_at * 1000).toLocaleString("vi-VN") : "Không giới hạn thời gian"}`));
      const toggle = text("button", code.active ? "Khóa mã" : "Mở mã"); toggle.type = "button";
      toggle.setAttribute("aria-label", `${toggle.textContent}: ${code.name}`);
      toggle.addEventListener("click", () => busy(toggle, async () => {
        try { await api(`codes/${code.code_hash}/active`, {active: !code.active}); await refresh(); }
        catch (error) { $("list-error").textContent = errorMessage(error); }
      }));
      row.append(details, toggle); return row;
    });
    $("codes").replaceChildren(...(rows.length ? rows : [text("p", "Chưa có mã trong cơ sở dữ liệu. Bạn có thể tạo mã đầu tiên ở phía trên.", "muted")]));
  } catch (error) {
    $("list-error").textContent = errorMessage(error);
    $("status").textContent = errorMessage(error);
  }
}

async function enter(session) {
  csrf = session.csrf;
  $("status").textContent = "";
  $("login-panel").hidden = true;
  $("dashboard").hidden = false;
  await refresh();
}

$("login-form").addEventListener("submit", (event) => {
  event.preventDefault();
  busy(event.submitter, async () => {
    $("login-error").textContent = "";
    try {
      const session = await api("login", {username: $("username").value, password: $("password").value});
      $("password").value = "";
      await enter(session);
    } catch (error) { $("login-error").textContent = errorMessage(error); }
  });
});
$("logout").addEventListener("click", (event) => busy(event.target, async () => {
  try { await api("logout", {}); showLogin(); $("status").textContent = "Đã đăng xuất."; $("username").focus(); }
  catch (error) { $("status").textContent = errorMessage(error); }
}));
$("refresh").addEventListener("click", (event) => busy(event.target, refresh));
$("reward-type").addEventListener("change", () => {
  const item = $("reward-type").value === "item";
  $("token-field").hidden = !item;
  $("token-id").required = item;
  $("token-id").disabled = !item;
  $("amount-label").textContent = item ? "Số lượng vật phẩm" : "Số vàng";
  $("amount").value = item ? "1" : "100";
});
$("gift-form").addEventListener("submit", (event) => {
  event.preventDefault();
  busy(event.submitter, async () => {
    $("gift-error").textContent = "";
    try {
      const result = await api("codes", {
        name: $("gift-name").value,
        reward_type: $("reward-type").value,
        token_id: $("reward-type").value === "item" ? Number($("token-id").value) : 0,
        amount: Number($("amount").value), max_uses: Number($("max-uses").value),
        expires_at: $("expires").value ? new Date($("expires").value).toISOString() : null,
      });
      $("new-code").value = result.code;
      $("qr-image").src = `data:image/png;base64,${result.qr_png}`;
      $("download-qr").href = $("qr-image").src;
      $("download-qr").download = `${result.code}.png`;
      $("preview-empty").hidden = true;
      $("preview-result").hidden = false;
      $("status").textContent = "Đã tạo mã. Hãy tải QR hoặc lưu mã trước khi rời trang.";
      $("download-qr").focus();
      await refresh();
    } catch (error) { $("gift-error").textContent = errorMessage(error); }
  });
});
api("me").then(enter).catch((error) => {
  showLogin();
  $("status").textContent = error.message.includes("đăng nhập") || error.message.includes("hết hạn") ? "" : errorMessage(error);
});
