const express = require('express');
const fetch = require('node-fetch');
const bodyParser = require('body-parser');
const cors = require('cors');

const app = express();
app.use(bodyParser.json());
app.use(cors());

// URL Google Apps Script для загрузки фото в Google Drive
const SCRIPT_URL = process.env.SCRIPT_URL || "https://script.google.com/macros/s/AKfycbz0ROkJVhliPpWSTlXqJbfqu4LXbRzvMxmWqWZv6jR2K14pBbxvVGsf8PBR-3mYzgda/exec";

app.post('/', async (req, res) => {
  try {
    console.log("POST request to script:", SCRIPT_URL);
    console.log("Request body:", JSON.stringify(req.body));
    
    const response = await fetch(SCRIPT_URL, {
      method: 'post',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body),
    });

    const contentType = response.headers.get('content-type');
    console.log("Response status:", response.status);
    console.log("Response content-type:", contentType);

    if (!contentType || !contentType.includes('application/json')) {
      const text = await response.text();
      console.error("Non-JSON response received:", text.substring(0, 200));
      throw new Error(`Сервер вернул HTML вместо JSON. Проверьте URL сервера: ${SCRIPT_URL}`);
    }

    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error("POST error:", error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при обращении к серверу'
    });
  }
});

app.get('/', async (req, res) => {
  try {
    console.log("GET request:", req.query);
    const queryString = new URLSearchParams(req.query).toString();
    const url = `${SCRIPT_URL}?${queryString}`;

    const response = await fetch(url);
    
    const contentType = response.headers.get('content-type');
    console.log("Response status:", response.status);
    console.log("Response content-type:", contentType);

    if (!contentType || !contentType.includes('application/json')) {
      const text = await response.text();
      console.error("Non-JSON response received:", text.substring(0, 200));
      throw new Error(`Сервер вернул HTML вместо JSON. Проверьте URL сервера: ${SCRIPT_URL}`);
    }

    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error("GET error:", error);
    res.status(500).json({ 
      success: false, 
      error: error.message || 'Ошибка при обращении к серверу'
    });
  }
});

app.listen(3000, () => console.log("Proxy listening on port 3000"));
