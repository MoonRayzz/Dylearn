const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");

// Inisialisasi Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

// Optimasi 1: Axios Instance dengan Timeout
const axiosClient = axios.create({
  timeout: 15000, 
});

// === GLOBAL REGEX & CONSTANTS (Optimasi Memori & Kompilasi) ===
const _reStorageUrl = /b\/(.*?)\/o\/(.*?)\?/;
const _reLtChar = /</g;
const _reGtChar = />/g;
const _reLtEntity = /&lt;/g;
const _reGtEntity = /&gt;/g;
const _pageBreakSplitter = "&lt;PAGE_BREAK&gt;";

// === MAPPING SIBI LEVEL ===
const SIBI_LEVELS = {
  "L1": "Bintang Kecil ⭐",
  "L2": "Petualang Kata 🎒",
  "L3": "Jagoan Baca 🦸‍♂️",
  "L4": "Kapten Cerita ⛵",
  "L5": "Master Buku 👑"
};

// === FUNGSI HELPER UNTUK MENGAMBIL KONFIGURASI TELEGRAM ===
let _cachedTgConfig = null; // Caching config agar tidak membaca process.env berkali-kali

function getTelegramConfig() {
  if (_cachedTgConfig) return _cachedTgConfig;

  const token = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID;
  if (!token || !chatId) {
    console.error("CRITICAL ERROR: Token atau Chat ID dari .env kosong/undefined!");
  }
  
  _cachedTgConfig = {
    botToken: token,
    chatId: chatId,
    apiUrl: `https://api.telegram.org/bot${token}`
  };
  
  return _cachedTgConfig;
}

/**
 * 1. FUNGSI PENGIRIM NOTIFIKASI KE TELEGRAM (DENGAN NAMA UPLOADER)
 */
exports.notifyAdminOnNewBook = onDocumentCreated("library_books/{bookId}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const newValue = snap.data();
  const bookId = event.params.bookId;

  if (newValue.status !== "review_admin") {
    return;
  }

  const tgConfig = getTelegramConfig();

  const title = newValue.title || "Tanpa Judul";
  const author = newValue.author || "Anonim";
  const category = newValue.category || "-";
  const coverUrl = newValue.coverUrl || "";
  const pageCount = newValue.pageCount || 0;
  const sibiLevel = newValue.sibiLevel || "Belum Tahu 🤷‍♂️";
  const uploadByUid = newValue.uploadBy; 

  let uploaderName = "Anonim (Tidak diketahui)";
  if (uploadByUid) {
    try {
      const userDoc = await db.collection("users").doc(uploadByUid).get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        uploaderName = userData.name || userData.displayName || userData.username || "Pengguna Tanpa Nama";
      } else {
        const userRecord = await admin.auth().getUser(uploadByUid);
        uploaderName = userRecord.displayName || "Pengguna Tanpa Nama";
      }
    } catch (e) {
      console.warn(`Gagal mencari nama untuk UID ${uploadByUid}:`, e.message);
    }
  }

  const sibiExplanation = 
    `\n\n📌 <b>PANDUAN LEVEL SIBI:</b>\n` +
    `• <b>Bintang Kecil ⭐</b> : Jenjang A (Pramembaca) - Teks sangat sedikit/Gambar besar.\n` +
    `• <b>Petualang Kata 🎒</b> : Jenjang B (Pembaca Awal) - Mulai lancar (SD Kelas 1-3).\n` +
    `• <b>Jagoan Baca 🦸‍♂️</b> : Jenjang C (Semenjana) - Cerita kompleks (SD Kelas 4-6).\n` +
    `• <b>Kapten Cerita ⛵</b> : Jenjang D (Madya) - Petualangan panjang (Setingkat SMP).\n` +
    `• <b>Master Buku 👑</b> : Jenjang E (Mahir) - Buku tebal/tantangan membaca.`;

  const captionText = 
    `📚 <b>BUKU BARU MENUNGGU PERSETUJUAN</b>\n\n` +
    `<b>Judul:</b> ${title}\n` +
    `<b>Penulis:</b> ${author}\n` +
    `<b>Kategori:</b> ${category}\n` +
    `<b>Halaman:</b> ${pageCount} Hal\n` +
    `<b>Diunggah Oleh:</b> 👤 ${uploaderName}\n` + 
    `<b>Level Pilihan Anak:</b> ${sibiLevel}` +
    sibiExplanation +
    `\n\n<i>Klik "Buka & Baca Buku Lengkap" untuk mengecek gambar dan isinya, lalu pilih level di bawah ini untuk menyetujui:</i>`;

  const viewUrl = `https://viewbook-lliu52dwza-uc.a.run.app?id=${bookId}`;

  const replyMarkup = {
    inline_keyboard: [
      [{ text: "📖 Buka & Baca Buku Lengkap", url: viewUrl }],
      [
        { text: "⭐ Bintang Kecil", callback_data: `L1_${bookId}` },
        { text: "🎒 Petualang Kata", callback_data: `L2_${bookId}` }
      ],
      [
        { text: "🦸‍♂️ Jagoan Baca", callback_data: `L3_${bookId}` },
        { text: "⛵ Kapten Cerita", callback_data: `L4_${bookId}` }
      ],
      [{ text: "👑 Master Buku", callback_data: `L5_${bookId}` }],
      [{ text: "❌ Tolak Buku", callback_data: `rej_${bookId}` }]
    ]
  };

  try {
    if (coverUrl.startsWith("http")) {
      await axiosClient.post(`${tgConfig.apiUrl}/sendPhoto`, {
        chat_id: tgConfig.chatId,
        photo: coverUrl,
        caption: captionText,
        parse_mode: "HTML",
        reply_markup: replyMarkup
      });
    } else {
      throw new Error("Tidak ada URL Cover valid.");
    }
  } catch (error) {
    console.warn("Gagal mengirim Foto. Fallback ke Teks biasa. Error:", error.message);
    try {
      const fallbackText = `⚠️ <i>(Sistem gagal memuat sampul)</i>\n\n${captionText}`;
      await axiosClient.post(`${tgConfig.apiUrl}/sendMessage`, {
        chat_id: tgConfig.chatId,
        text: fallbackText,
        parse_mode: "HTML",
        reply_markup: replyMarkup,
        disable_web_page_preview: true
      });
    } catch (err2) {
      console.error("Critical Error: Telegram Fallback juga gagal.", err2.message);
    }
  }
});

/**
 * 2. FUNGSI PENERIMA (WEBHOOK V2 - MENGHAPUS TOMBOL & CLEANUP STORAGE)
 */
exports.telegramWebhook = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const update = req.body;

  if (update.callback_query) {
    const callbackQuery = update.callback_query;
    const data = callbackQuery.data; 
    const message = callbackQuery.message;
    const chatId = message.chat.id;
    const messageId = message.message_id;

    const tgConfig = getTelegramConfig();

    let newStatus = "";
    let actionText = "";
    let bookId = "";
    let updatedSibiLevel = "";

    if (data.startsWith("rej_")) {
      bookId = data.replace("rej_", "");
      newStatus = "rejected"; 
      actionText = "❌ BUKU DITOLAK\nSistem telah membersihkan semua file gambar dan teks.";
      
      // =========================================================================
      // [FITUR BARU] AUTO-CLEANUP: Menghapus file fisik di Storage & Isi Teks
      // =========================================================================
      try {
        const docRef = db.collection("library_books").doc(bookId);
        const docSnap = await docRef.get();
        
        if (docSnap.exists) {
          const bookData = docSnap.data();
          const urlsToDelete = [];

          if (bookData.coverUrl) urlsToDelete.push(bookData.coverUrl);
          if (bookData.imageUrls && Array.isArray(bookData.imageUrls)) {
            urlsToDelete.push(...bookData.imageUrls);
          }

          // Proses Ekstrak Bucket & Path dari URL lalu hapus dari Firebase Storage
          urlsToDelete.forEach(url => {
            try {
              // Menggunakan _reStorageUrl yang sudah di-hoist di luar agar tidak re-compile di dalam loop
              const match = url.match(_reStorageUrl);
              if (match && match.length === 3) {
                const bucketName = match[1];
                const filePath = decodeURIComponent(match[2]); 
                
                admin.storage().bucket(bucketName).file(filePath).delete()
                  .then(() => console.log(`Berhasil hapus junk file: ${filePath}`))
                  .catch(err => console.warn(`Gagal hapus file ${filePath}:`, err.message));
              }
            } catch (parseError) {
              console.warn("Gagal mengekstrak URL:", url);
            }
          });

          // Hapus URL gambar dan Hapus Teks Cerita/OCR dari Firestore
          await docRef.update({
            coverUrl: "",
            imageUrls: [],
            imageUrl: "",
            content: "", // ✅ Menghapus teks cerita
            ocrText: ""  // ✅ Menghapus teks OCR
          });
        }
      } catch (cleanupError) {
        console.error("Error saat menjalankan Auto-Cleanup:", cleanupError.message);
      }
      // =========================================================================

    } else {
      const levelCode = data.substring(0, 2); 
      bookId = data.substring(3); 
      
      if (SIBI_LEVELS[levelCode]) {
        newStatus = "pending"; 
        updatedSibiLevel = SIBI_LEVELS[levelCode];
        actionText = `✅ BUKU DISETUJUI\nLevel Akhir: ${updatedSibiLevel}`;
      }
    }

    if (bookId !== "") {
      try {
        const updateData = { status: newStatus };
        if (updatedSibiLevel !== "") {
          updateData.sibiLevel = updatedSibiLevel;
        }
        
        const dbUpdatePromise = db.collection("library_books").doc(bookId).update(updateData);

        const updatedCaption = `${message.caption || message.text}\n\n<b>STATUS: ${actionText}</b>`;
        
        const editPayload = {
          chat_id: chatId,
          message_id: messageId,
          parse_mode: "HTML",
          reply_markup: { inline_keyboard: [] } 
        };

        let telegramEditPromise;
        if (message.photo) {
          editPayload.caption = updatedCaption;
          telegramEditPromise = axiosClient.post(`${tgConfig.apiUrl}/editMessageCaption`, editPayload);
        } else {
          editPayload.text = updatedCaption;
          telegramEditPromise = axiosClient.post(`${tgConfig.apiUrl}/editMessageText`, editPayload);
        }

        const telegramAnswerPromise = axiosClient.post(`${tgConfig.apiUrl}/answerCallbackQuery`, {
          callback_query_id: callbackQuery.id,
          text: `Aksi berhasil dicatat!`
        });

        await Promise.all([dbUpdatePromise, telegramEditPromise, telegramAnswerPromise]);

      } catch (error) {
        console.error("Gagal memproses Webhook:", error.message);
      }
    }
  }

  res.status(200).send("OK");
});

/**
 * 3. FUNGSI WEB VIEWER DENGAN FITUR DELETE HALAMAN
 */
exports.viewBook = onRequest(async (req, res) => {
  const bookId = req.query.id;

  if (!bookId) {
    return res.status(400).send("ID Buku tidak disertakan.");
  }

  try {
    const doc = await db.collection("library_books").doc(bookId).get();
    
    if (!doc.exists) {
      return res.status(404).send("<h2 style='font-family: sans-serif; text-align: center; margin-top: 50px;'>Buku tidak ditemukan atau sudah dihapus.</h2>");
    }

    const data = doc.data();
    const title = data.title || "Tanpa Judul";
    const author = data.author || "Anonim";
    const category = data.category || "-";
    const imageUrls = data.imageUrls || [];
    let textContent = data.content || data.ocrText || "";

    const updateUrl = `https://updatebooktext-lliu52dwza-uc.a.run.app`;

    // Menggunakan regex global yang sudah di-hoist
    textContent = textContent.replace(_reLtChar, "&lt;").replace(_reGtChar, "&gt;");
    
    // Split menggunakan constant string (lebih cepat daripada regex split)
    let textPages = textContent.split(_pageBreakSplitter).map(t => t.trim());

    if (imageUrls.length === 0) {
      imageUrls.push("https://via.placeholder.com/600x800/e0e0e0/555555?text=Tidak+Ada+Gambar");
    }

    while (textPages.length < imageUrls.length) {
      textPages.push("");
    }
    if (textPages.length > imageUrls.length) {
      const extraTexts = textPages.splice(imageUrls.length - 1);
      textPages.push(extraTexts.join("\n\n"));
    }

    const clientData = {
      bookId: bookId,
      images: imageUrls,
      texts: textPages,
      updateUrl: updateUrl
    };

    const html = `
    <!DOCTYPE html>
    <html lang="id">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <title>Dylearn Workspace: ${title}</title>
      <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
      <style>
        :root {
          --primary: #f59e0b;
          --primary-hover: #d97706;
          --danger: #ef4444;
          --danger-hover: #dc2626;
          --bg-body: #f3f4f6;
          --bg-surface: #ffffff;
          --text-main: #1f2937;
          --text-muted: #6b7280;
          --border: #e5e7eb;
          --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        }

        body { font-family: 'Inter', sans-serif; background-color: var(--bg-body); color: var(--text-main); margin: 0; padding: 0; height: 100vh; display: flex; flex-direction: column; }
        
        .navbar { background-color: var(--bg-surface); padding: 16px 24px; border-bottom: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; z-index: 10; }
        .nav-info { flex: 1; min-width: 0; padding-right: 16px; }
        .nav-title { margin: 0 0 4px 0; font-size: 18px; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .nav-meta { margin: 0; font-size: 13px; color: var(--text-muted); }
        .badge { background: #fef3c7; color: #b45309; padding: 6px 12px; border-radius: 9999px; font-size: 12px; font-weight: 600; white-space: nowrap;}

        .workspace { display: flex; flex: 1; overflow: hidden; }

        .pane-image { flex: 1; background-color: #e5e7eb; display: flex; flex-direction: column; position: relative; border-right: 1px solid var(--border); }
        .image-wrapper { flex: 1; overflow: auto; display: flex; justify-content: center; align-items: center; padding: 24px; position: relative; }
        
        .preview-img { max-width: 100%; max-height: 100%; object-fit: contain; border-radius: 8px; box-shadow: var(--shadow-md); background-color: white; transition: opacity 0.2s ease; }
        
        .btn-delete-page {
          position: absolute;
          top: 16px;
          right: 16px;
          background: rgba(239, 68, 68, 0.9);
          color: white;
          border: none;
          padding: 8px 12px;
          border-radius: 6px;
          font-size: 13px;
          font-weight: 600;
          cursor: pointer;
          backdrop-filter: blur(4px);
          box-shadow: 0 2px 5px rgba(0,0,0,0.2);
          transition: background 0.2s;
          display: flex;
          align-items: center;
          gap: 6px;
        }
        .btn-delete-page:hover { background: var(--danger); }

        .controls-container { background-color: var(--bg-surface); padding: 12px 24px; border-top: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; }
        .btn-page { background-color: white; border: 1px solid var(--border); padding: 8px 16px; border-radius: 6px; font-weight: 600; font-size: 14px; cursor: pointer; transition: all 0.2s; }
        .btn-page:hover:not(:disabled) { background-color: #f9fafb; }
        .btn-page:disabled { color: #9ca3af; cursor: not-allowed; background-color: #f3f4f6; }
        .page-indicator { font-weight: 600; font-size: 14px; color: var(--text-muted); }

        .pane-editor { flex: 1; background-color: var(--bg-surface); display: flex; flex-direction: column; }
        .editor-header { padding: 20px 24px 16px 24px; border-bottom: 1px solid var(--border); }
        .editor-title { margin: 0 0 4px 0; font-size: 16px; font-weight: 600; }
        .editor-desc { margin: 0; font-size: 13px; color: var(--text-muted); }
        
        .textarea-container { flex: 1; padding: 24px; display: flex; flex-direction: column; }
        .text-editor { flex: 1; width: 100%; box-sizing: border-box; background: #fdfdfd; padding: 20px; border: 1px solid #e5e7eb; border-radius: 8px; font-size: 15px; line-height: 1.8; resize: none; }
        .text-editor:focus { outline: none; border-color: var(--primary); box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.15); }

        .action-footer { padding: 16px 24px; background-color: var(--bg-surface); border-top: 1px solid var(--border); display: flex; justify-content: space-between; align-items: center; }
        .status-msg { font-size: 14px; font-weight: 500; }
        .status-success { color: #10b981; }
        .status-error { color: #ef4444; }
        .status-warning { color: #f59e0b; }

        .btn-save { background-color: var(--primary); color: white; border: none; padding: 12px 24px; font-size: 14px; font-weight: 600; border-radius: 6px; cursor: pointer; transition: 0.2s; }
        .btn-save:hover:not(:disabled) { background-color: var(--primary-hover); }
        .btn-save:disabled { background-color: #d1d5db; cursor: not-allowed; }

        @media (max-width: 768px) {
          .workspace { flex-direction: column; overflow: visible; }
          .pane-image { height: 40vh; flex: none; border-right: none; }
          .text-editor { min-height: 300px; }
          .action-footer { position: sticky; bottom: 0; flex-direction: column; gap: 12px; }
          .btn-save { width: 100%; }
        }

        .loading-overlay { position: absolute; top: 0; left: 0; right: 0; bottom: 0; background: rgba(229, 231, 235, 0.7); display: flex; justify-content: center; align-items: center; opacity: 0; pointer-events: none; transition: opacity 0.2s; }
        .loading-overlay.active { opacity: 1; pointer-events: all; }
        .spinner { width: 40px; height: 40px; border: 4px solid var(--primary); border-bottom-color: transparent; border-radius: 50%; animation: spin 1s linear infinite; }
        @keyframes spin { 100% { transform: rotate(360deg); } }
      </style>
    </head>
    <body>
      
      <header class="navbar">
        <div class="nav-info">
          <h1 class="nav-title">${title}</h1>
          <p class="nav-meta">Oleh: <b>${author}</b></p>
        </div>
        <span class="badge">${category}</span>
      </header>

      <main class="workspace">
        <section class="pane-image">
          <div class="image-wrapper">
            <img id="elImage" class="preview-img" src="" alt="Loading..." />
            <div id="imgLoader" class="loading-overlay"><div class="spinner"></div></div>
          </div>
          
          <button class="btn-delete-page" onclick="deleteCurrentPage()">
            <span style="font-size:16px">🗑️</span> Hapus Hal Ini
          </button>

          <div class="controls-container">
            <button id="btnPrev" class="btn-page" onclick="changePage(-1)">← Prev</button>
            <span id="elIndicator" class="page-indicator">Hal 1 / 1</span>
            <button id="btnNext" class="btn-page" onclick="changePage(1)">Next →</button>
          </div>
        </section>

        <section class="pane-editor">
          <div class="editor-header">
            <h3 class="editor-title"><span>✍️</span> Editor Teks Halaman <span id="elHeaderPage">1</span></h3>
            <p class="editor-desc">Perbaiki typo pada gambar, atau hapus halaman jika tidak penting.</p>
          </div>
          
          <div class="textarea-container">
            <textarea id="elEditor" class="text-editor" spellcheck="false" placeholder="Teks tidak ditemukan di halaman ini..."></textarea>
          </div>
          
          <div class="action-footer">
            <span id="elStatus" class="status-msg"></span>
            <button id="btnSave" class="btn-save" onclick="saveAllToDatabase()">💾 Simpan Semua Perubahan</button>
          </div>
        </section>
      </main>

      <script>
        const appData = ${JSON.stringify(clientData)};
        let currentPage = 0;
        
        let localImages = [...appData.images];
        let localTexts = [...appData.texts];
        
        const imageCache = new Map();

        const elImage = document.getElementById('elImage');
        const elEditor = document.getElementById('elEditor');
        const elIndicator = document.getElementById('elIndicator');
        const elHeaderPage = document.getElementById('elHeaderPage');
        const btnPrev = document.getElementById('btnPrev');
        const btnNext = document.getElementById('btnNext');
        const btnSave = document.getElementById('btnSave');
        const elStatus = document.getElementById('elStatus');
        const imgLoader = document.getElementById('imgLoader');

        function preloadImages() {
          localImages.forEach((url, index) => {
            const img = new Image();
            img.src = url;
            img.onload = () => { imageCache.set(index, url); };
          });
        }

        function renderCurrentPage() {
          if (localImages.length === 0) {
            elImage.style.display = 'none';
            elEditor.value = "Semua halaman telah dihapus.";
            elEditor.disabled = true;
            elIndicator.innerText = '0 / 0';
            btnPrev.disabled = true;
            btnNext.disabled = true;
            return;
          }

          elImage.style.opacity = '0.5';
          imgLoader.classList.add('active');
          
          const newSrc = localImages[currentPage];
          
          if (imageCache.has(currentPage)) {
             elImage.src = newSrc;
             elImage.style.opacity = '1';
             imgLoader.classList.remove('active');
          } else {
             elImage.src = newSrc;
             elImage.onload = () => {
               elImage.style.opacity = '1';
               imgLoader.classList.remove('active');
               imageCache.set(currentPage, newSrc);
             };
          }
          
          elEditor.value = localTexts[currentPage];
          elIndicator.innerText = \`Hal \${currentPage + 1} / \${localImages.length}\`;
          elHeaderPage.innerText = currentPage + 1;
          btnPrev.disabled = currentPage === 0;
          btnNext.disabled = currentPage === localImages.length - 1;
        }

        elEditor.addEventListener('input', (e) => {
          localTexts[currentPage] = e.target.value;
          elStatus.innerText = "⚠️ Ada perubahan yang belum disimpan.";
          elStatus.className = "status-msg status-warning";
        });

        function changePage(direction) {
          if (localImages.length === 0) return;
          localTexts[currentPage] = elEditor.value;
          let newPage = currentPage + direction;
          if (newPage >= 0 && newPage < localImages.length) {
            currentPage = newPage;
            renderCurrentPage();
          }
        }

        function deleteCurrentPage() {
          if (localImages.length <= 1) {
            alert("Minimal harus ada 1 halaman buku. Jika ingin menghapus buku sepenuhnya, gunakan tombol Tolak di Telegram.");
            return;
          }

          const isConfirmed = confirm("Yakin ingin menghapus halaman " + (currentPage + 1) + " ini beserta teksnya?");
          if (!isConfirmed) return;

          localImages.splice(currentPage, 1);
          localTexts.splice(currentPage, 1);

          if (currentPage >= localImages.length) {
            currentPage = localImages.length - 1;
          }

          elStatus.innerText = "⚠️ Halaman terhapus. Jangan lupa klik 'Simpan' untuk mematenkan perubahan.";
          elStatus.className = "status-msg status-warning";

          imageCache.clear();
          preloadImages();

          renderCurrentPage();
        }

        document.addEventListener('keydown', (e) => {
          if (document.activeElement === elEditor) return;
          if (e.key === 'ArrowRight') changePage(1);
          else if (e.key === 'ArrowLeft') changePage(-1);
        });

        if (localImages.length > 0) {
          renderCurrentPage();
          preloadImages(); 
        }

        async function saveAllToDatabase() {
          if(localImages.length > 0) {
            localTexts[currentPage] = elEditor.value;
          }

          const finalCombinedText = localTexts.join("\\n\\n<PAGE_BREAK>\\n\\n");

          btnSave.disabled = true;
          btnSave.innerText = '⏳ Menyimpan...';
          elStatus.innerText = '';

          try {
            const response = await fetch(appData.updateUrl, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ 
                bookId: appData.bookId, 
                newText: finalCombinedText,
                newImageUrls: localImages 
              })
            });

            if (response.ok) {
              elStatus.innerText = '✅ Berhasil disimpan! Silakan kembali ke Telegram.';
              elStatus.className = "status-msg status-success";
            } else {
              throw new Error('Server menolak permintaan.');
            }
          } catch (e) {
            console.error(e);
            elStatus.innerText = '❌ Gagal menyimpan. Silakan coba lagi.';
            elStatus.className = "status-msg status-error";
          } finally {
            btnSave.disabled = false;
            btnSave.innerText = '💾 Simpan Semua Perubahan';
            if(elStatus.className.includes("status-success")) {
               setTimeout(() => { elStatus.innerText = ''; }, 5000);
            }
          }
        }
      </script>
    </body>
    </html>
    `;

    res.status(200).send(html);

  } catch (error) {
    console.error("Error memuat buku:", error);
    res.status(500).send("<h2 style='text-align:center; font-family:sans-serif; margin-top:50px; color:#ef4444;'>Terjadi kesalahan sistem saat memuat dokumen.</h2>");
  }
});

/**
 * 4. FUNGSI BARU: API UNTUK MENYIMPAN UPDATE TEKS & GAMBAR KE FIRESTORE
 */
exports.updateBookText = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }

  const { bookId, newText, newImageUrls } = req.body;

  if (!bookId || newText === undefined) {
    return res.status(400).send('Data tidak valid (bookId atau newText kosong).');
  }

  try {
    // Menggunakan regex global yang sudah di-hoist
    const decodedText = newText.replace(_reLtEntity, "<").replace(_reGtEntity, ">");
    
    const updateData = {
      content: decodedText,
      ocrText: decodedText
    };

    if (newImageUrls && Array.isArray(newImageUrls)) {
      updateData.imageUrls = newImageUrls;
      updateData.pageCount = newImageUrls.length; 
      
      if (newImageUrls.length > 0) {
        updateData.imageUrl = newImageUrls[0];
      }
    }

    await db.collection("library_books").doc(bookId).update(updateData);
    
    console.log(`Buku ${bookId} berhasil diupdate (Teks dan/atau Gambar).`);
    res.status(200).send('Berhasil update');
  } catch (error) {
    console.error("Gagal update buku:", error);
    res.status(500).send('Terjadi kesalahan server saat menyimpan.');
  }
});