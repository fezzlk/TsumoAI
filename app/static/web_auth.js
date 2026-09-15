// Authentication for optional submissions and administrator dataset actions.
// Public scoring and recognition requests keep using fetch directly.
(() => {
  const status = document.getElementById("webAuthStatus");
  const login = document.getElementById("webLoginBtn");
  const logout = document.getElementById("webLogoutBtn");
  const listeners = new Set();
  let auth;
  let user = null;
  let isAdmin = false;
  let initialized = false;
  let generation = 0;
  let sessionGeneration = 0;
  let resolveReady;
  const ready = new Promise((resolve) => { resolveReady = resolve; });

  function publish() {
    initialized = true;
    login.hidden = !!user;
    logout.hidden = !user;
    resolveReady();
    listeners.forEach((listener) => listener({ user, isAdmin }));
  }

  window.TsumoAuth = {
    ready,
    get user() { return user; },
    get isAdmin() { return isAdmin; },
    get sessionGeneration() { return sessionGeneration; },
    isCurrentSession(expectedUser, expectedGeneration) {
      return (auth?.currentUser || null) === expectedUser && sessionGeneration === expectedGeneration;
    },
    subscribe(listener) {
      listeners.add(listener);
      if (initialized) listener({ user, isAdmin });
      return () => listeners.delete(listener);
    },
    async fetch(url, options = {}, { admin = false } = {}) {
      await ready;
      const currentUser = auth?.currentUser;
      if (!currentUser) throw new Error("Googleでログインしてから操作してください。");
      const requestGeneration = sessionGeneration;
      const checkSession = () => {
        if (auth.currentUser !== currentUser || sessionGeneration !== requestGeneration) {
          throw new Error("ログイン状態が変わりました。内容を確認して再度操作してください。");
        }
      };
      let token;
      try {
        token = await currentUser.getIdTokenResult();
      } catch (_error) {
        throw new Error("認証を確認できません。通信状態を確認し、再度ログインしてください。");
      }
      checkSession();
      if (admin && token.claims.admin !== true) {
        throw new Error("データセットの一覧・ダウンロードには管理者権限が必要です。");
      }
      const headers = new Headers(options.headers || {});
      headers.set("Authorization", `Bearer ${token.token}`);
      const response = await fetch(url, { ...options, headers });
      checkSession();
      if (response.status === 401) {
        throw new Error("認証の有効期限が切れています。再度ログインしてください。");
      }
      if (response.status === 403) {
        throw new Error("この操作には管理者権限が必要です。");
      }
      return response;
    },
  };

  try {
    firebase.initializeApp(window.TsumoFirebaseConfig);
    auth = firebase.auth();
    auth.onIdTokenChanged(async (nextUser) => {
      const currentGeneration = ++generation;
      // A token refresh for the same user remains part of the same session.
      // Logging out and back in invalidates pending work even for the same user.
      if (nextUser !== user) ++sessionGeneration;
      user = nextUser;
      isAdmin = false;
      let error = "";
      if (user) {
        try {
          const token = await user.getIdTokenResult();
          if (currentGeneration !== generation) return;
          isAdmin = token.claims.admin === true;
        } catch (_error) {
          error = "（認証を確認できません。通信状態を確認してください。）";
        }
      }
      if (currentGeneration !== generation) return;
      status.textContent = user
        ? `${user.email || user.displayName || "ユーザー"} でログイン中${isAdmin ? "（管理者）" : ""}${error}`
        : "未ログインです。投稿するには Google でログインしてください。";
      publish();
    }, (error) => {
      status.textContent = `認証を確認できません: ${error.message}`;
      publish();
    });
  } catch (_error) {
    status.textContent = "ログイン機能を読み込めません。通信状態を確認して再読み込みしてください。";
    login.disabled = true;
    publish();
  }

  login.addEventListener("click", async () => {
    login.disabled = true;
    try {
      await auth.signInWithPopup(new firebase.auth.GoogleAuthProvider());
    } catch (error) {
      status.textContent = `ログイン失敗: ${error.message}`;
    } finally {
      login.disabled = false;
    }
  });
  logout.addEventListener("click", async () => {
    try {
      await auth.signOut();
    } catch (error) {
      status.textContent = `ログアウト失敗: ${error.message}`;
    }
  });
})();
