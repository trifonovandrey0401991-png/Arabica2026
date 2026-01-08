// ========== Personal Product Question Dialogs API ==========
const PRODUCT_QUESTION_DIALOGS_DIR = "/var/www/product-question-dialogs";

// Ensure directory exists
if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
  fs.mkdirSync(PRODUCT_QUESTION_DIALOGS_DIR, { recursive: true });
}

// Helper: Generate dialog ID
function generateDialogId() {
  return "dialog_" + Date.now() + "_" + Math.random().toString(36).substr(2, 9);
}

// POST /api/product-question-dialogs - Create a new personal dialog
app.post("/api/product-question-dialogs", async (req, res) => {
  try {
    const { clientPhone, clientName, shopAddress, originalQuestionId, initialMessage, imageUrl } = req.body;
    console.log("POST /api/product-question-dialogs", { clientPhone, shopAddress, originalQuestionId });

    if (!clientPhone || !shopAddress) {
      return res.status(400).json({ success: false, error: "Missing required fields" });
    }

    const dialogId = generateDialogId();
    const timestamp = new Date().toISOString();

    const dialog = {
      id: dialogId,
      clientPhone,
      clientName: clientName || "Клиент",
      shopAddress,
      originalQuestionId: originalQuestionId || null,
      createdAt: timestamp,
      hasUnreadFromClient: false,
      hasUnreadFromEmployee: false,
      lastMessageTime: timestamp,
      messages: []
    };

    // Add initial message if provided
    if (initialMessage) {
      dialog.messages.push({
        id: "msg_" + Date.now(),
        senderType: "client",
        senderPhone: clientPhone,
        senderName: clientName || "Клиент",
        text: initialMessage,
        imageUrl: imageUrl || null,
        timestamp
      });
      dialog.hasUnreadFromClient = true;
    }

    // Save dialog
    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, dialogId + ".json");
    fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), "utf8");

    console.log("Personal dialog created: " + dialogId);
    res.json({ success: true, dialogId, dialog });
  } catch (err) {
    console.error("Error creating personal dialog:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/client/:phone - Get all dialogs for a client
app.get("/api/product-question-dialogs/client/:phone", async (req, res) => {
  try {
    const { phone } = req.params;
    const normalizedPhone = phone.replace(/[\s+]/g, "");
    console.log("GET /api/product-question-dialogs/client/:phone", normalizedPhone);

    if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
      return res.json({ success: true, dialogs: [] });
    }

    const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith(".json"));
    let dialogs = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), "utf8");
        const dialog = JSON.parse(content);

        if (dialog.clientPhone.replace(/[\s+]/g, "") === normalizedPhone) {
          const lastMsg = dialog.messages.length > 0 ? dialog.messages[dialog.messages.length - 1] : null;
          dialogs.push({
            id: dialog.id,
            clientPhone: dialog.clientPhone,
            clientName: dialog.clientName,
            shopAddress: dialog.shopAddress,
            createdAt: dialog.createdAt,
            lastMessageTime: dialog.lastMessageTime,
            hasUnreadFromEmployee: dialog.hasUnreadFromEmployee || false,
            hasUnreadFromClient: dialog.hasUnreadFromClient || false,
            messages: dialog.messages,
            lastMessage: lastMsg ? {
              text: lastMsg.text,
              timestamp: lastMsg.timestamp,
              senderType: lastMsg.senderType
            } : null
          });
        }
      } catch (e) {
        console.error("Error parsing dialog file:", file, e.message);
      }
    }

    // Sort by last message time (newest first)
    dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

    console.log("Loaded " + dialogs.length + " dialogs for client " + normalizedPhone);
    res.json({ success: true, dialogs });
  } catch (err) {
    console.error("Error loading client dialogs:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/shop/:shopAddress - Get all dialogs for a shop (for employees)
app.get("/api/product-question-dialogs/shop/:shopAddress", async (req, res) => {
  try {
    const { shopAddress } = req.params;
    const decodedAddress = decodeURIComponent(shopAddress);
    console.log("GET /api/product-question-dialogs/shop/:shopAddress", decodedAddress);

    if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
      return res.json({ success: true, dialogs: [] });
    }

    const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith(".json"));
    let dialogs = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), "utf8");
        const dialog = JSON.parse(content);

        if (dialog.shopAddress === decodedAddress) {
          const lastMsg = dialog.messages.length > 0 ? dialog.messages[dialog.messages.length - 1] : null;
          dialogs.push({
            id: dialog.id,
            clientPhone: dialog.clientPhone,
            clientName: dialog.clientName,
            shopAddress: dialog.shopAddress,
            createdAt: dialog.createdAt,
            lastMessageTime: dialog.lastMessageTime,
            hasUnreadFromClient: dialog.hasUnreadFromClient || false,
            hasUnreadFromEmployee: dialog.hasUnreadFromEmployee || false,
            messages: dialog.messages,
            lastMessage: lastMsg ? {
              text: lastMsg.text,
              timestamp: lastMsg.timestamp,
              senderType: lastMsg.senderType
            } : null
          });
        }
      } catch (e) {
        console.error("Error parsing dialog file:", file, e.message);
      }
    }

    // Sort by last message time (newest first)
    dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

    console.log("Loaded " + dialogs.length + " dialogs for shop " + decodedAddress);
    res.json({ success: true, dialogs });
  } catch (err) {
    console.error("Error loading shop dialogs:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/all - Get all dialogs (for employees viewing all)
app.get("/api/product-question-dialogs/all", async (req, res) => {
  try {
    console.log("GET /api/product-question-dialogs/all");

    if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
      return res.json({ success: true, dialogs: [] });
    }

    const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith(".json"));
    let dialogs = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PRODUCT_QUESTION_DIALOGS_DIR, file), "utf8");
        const dialog = JSON.parse(content);

        const lastMsg = dialog.messages.length > 0 ? dialog.messages[dialog.messages.length - 1] : null;
        dialogs.push({
          id: dialog.id,
          clientPhone: dialog.clientPhone,
          clientName: dialog.clientName,
          shopAddress: dialog.shopAddress,
          createdAt: dialog.createdAt,
          lastMessageTime: dialog.lastMessageTime,
          hasUnreadFromClient: dialog.hasUnreadFromClient || false,
          hasUnreadFromEmployee: dialog.hasUnreadFromEmployee || false,
          messages: dialog.messages,
          lastMessage: lastMsg ? {
            text: lastMsg.text,
            timestamp: lastMsg.timestamp,
            senderType: lastMsg.senderType
          } : null
        });
      } catch (e) {
        console.error("Error parsing dialog file:", file, e.message);
      }
    }

    // Sort by last message time (newest first)
    dialogs.sort((a, b) => new Date(b.lastMessageTime) - new Date(a.lastMessageTime));

    console.log("Loaded " + dialogs.length + " total dialogs");
    res.json({ success: true, dialogs });
  } catch (err) {
    console.error("Error loading all dialogs:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/product-question-dialogs/:id - Get a single dialog
app.get("/api/product-question-dialogs/:id", async (req, res) => {
  try {
    const { id } = req.params;
    console.log("GET /api/product-question-dialogs/:id", id);

    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, id + ".json");
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: "Dialog not found" });
    }

    const content = fs.readFileSync(filePath, "utf8");
    const dialog = JSON.parse(content);

    res.json({ success: true, dialog });
  } catch (err) {
    console.error("Error loading dialog:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/product-question-dialogs/:id/messages - Send message in dialog
app.post("/api/product-question-dialogs/:id/messages", async (req, res) => {
  try {
    const { id } = req.params;
    const { senderType, senderPhone, senderName, text, imageUrl } = req.body;
    console.log("POST /api/product-question-dialogs/:id/messages", { id, senderType, senderName });

    if (!text || !senderType) {
      return res.status(400).json({ success: false, error: "Missing required fields" });
    }

    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, id + ".json");
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: "Dialog not found" });
    }

    const content = fs.readFileSync(filePath, "utf8");
    const dialog = JSON.parse(content);

    const timestamp = new Date().toISOString();
    const message = {
      id: "msg_" + Date.now(),
      senderType,
      senderPhone: senderPhone || null,
      senderName: senderName || (senderType === "client" ? "Клиент" : "Сотрудник"),
      text,
      imageUrl: imageUrl || null,
      timestamp
    };

    dialog.messages.push(message);
    dialog.lastMessageTime = timestamp;

    // Update unread flags
    if (senderType === "client") {
      dialog.hasUnreadFromClient = true;
      dialog.hasUnreadFromEmployee = false;
    } else {
      dialog.hasUnreadFromEmployee = true;
      dialog.hasUnreadFromClient = false;
    }

    fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), "utf8");

    console.log("Message added to dialog " + id);
    res.json({ success: true, message });
  } catch (err) {
    console.error("Error adding message to dialog:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/product-question-dialogs/:id/mark-read - Mark as read
app.post("/api/product-question-dialogs/:id/mark-read", async (req, res) => {
  try {
    const { id } = req.params;
    const { readerType } = req.body; // "client" or "employee"
    console.log("POST /api/product-question-dialogs/:id/mark-read", { id, readerType });

    const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, id + ".json");
    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ success: false, error: "Dialog not found" });
    }

    const content = fs.readFileSync(filePath, "utf8");
    const dialog = JSON.parse(content);

    if (readerType === "client") {
      dialog.hasUnreadFromEmployee = false;
    } else if (readerType === "employee") {
      dialog.hasUnreadFromClient = false;
    }

    fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), "utf8");

    console.log("Dialog " + id + " marked as read by " + readerType);
    res.json({ success: true });
  } catch (err) {
    console.error("Error marking dialog as read:", err);
    res.status(500).json({ success: false, error: err.message });
  }
});

