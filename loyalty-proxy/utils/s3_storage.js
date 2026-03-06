/**
 * S3 Storage Module (Yandex Object Storage — S3-compatible)
 *
 * Utility for archiving old messenger media files to cloud storage.
 * Uses @aws-sdk/client-s3 which is compatible with Yandex Object Storage.
 *
 * Environment variables:
 * - S3_ARCHIVE_ENABLED=true/false (feature flag, default: false)
 * - S3_ENDPOINT=https://storage.yandexcloud.net
 * - S3_BUCKET=arabica-media-archive
 * - S3_ACCESS_KEY=<key>
 * - S3_SECRET_KEY=<secret>
 * - S3_REGION=ru-central1
 */

const fs = require('fs');
const path = require('path');

const S3_ARCHIVE_ENABLED = process.env.S3_ARCHIVE_ENABLED === 'true';
const S3_ENDPOINT = process.env.S3_ENDPOINT || 'https://storage.yandexcloud.net';
const S3_BUCKET = process.env.S3_BUCKET || 'arabica-media-archive';
const S3_ACCESS_KEY = process.env.S3_ACCESS_KEY || '';
const S3_SECRET_KEY = process.env.S3_SECRET_KEY || '';
const S3_REGION = process.env.S3_REGION || 'ru-central1';

let s3Client = null;

/** Content type mapping by file extension */
const CONTENT_TYPES = {
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png',
  '.gif': 'image/gif', '.webp': 'image/webp',
  '.mp4': 'video/mp4', '.mov': 'video/quicktime', '.webm': 'video/webm',
  '.m4a': 'audio/mp4', '.aac': 'audio/aac', '.ogg': 'audio/ogg',
  '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.opus': 'audio/opus',
  '.pdf': 'application/pdf', '.doc': 'application/msword',
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls': 'application/vnd.ms-excel',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.zip': 'application/zip', '.txt': 'text/plain', '.csv': 'text/csv',
};

/**
 * Lazy init — S3Client is created only on first use.
 * If feature is disabled, there is zero overhead.
 */
function getClient() {
  if (s3Client) return s3Client;

  if (!S3_ACCESS_KEY || !S3_SECRET_KEY) {
    throw new Error('S3 credentials not configured (S3_ACCESS_KEY / S3_SECRET_KEY)');
  }

  const { S3Client } = require('@aws-sdk/client-s3');
  s3Client = new S3Client({
    endpoint: S3_ENDPOINT,
    region: S3_REGION,
    credentials: {
      accessKeyId: S3_ACCESS_KEY,
      secretAccessKey: S3_SECRET_KEY,
    },
    forcePathStyle: true, // Required for Yandex Object Storage
  });

  return s3Client;
}

/**
 * Upload a local file to S3 bucket.
 * @param {string} localFilePath - full path to local file
 * @param {string} key - S3 object key (usually just the filename)
 * @returns {Promise<boolean>} true if uploaded successfully
 */
async function uploadFile(localFilePath, key) {
  const { PutObjectCommand } = require('@aws-sdk/client-s3');
  const client = getClient();
  const fileStream = fs.createReadStream(localFilePath);

  const ext = path.extname(key).toLowerCase();
  const contentType = CONTENT_TYPES[ext] || 'application/octet-stream';

  await client.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: `messenger-media/${key}`,
    Body: fileStream,
    ContentType: contentType,
  }));

  return true;
}

/**
 * Get a readable stream from S3 for proxying to client.
 * @param {string} key - S3 object key (filename)
 * @returns {Promise<{stream: ReadableStream, contentType: string, contentLength: number}>}
 */
async function getFileStream(key) {
  const { GetObjectCommand } = require('@aws-sdk/client-s3');
  const client = getClient();

  const response = await client.send(new GetObjectCommand({
    Bucket: S3_BUCKET,
    Key: `messenger-media/${key}`,
  }));

  return {
    stream: response.Body,
    contentType: response.ContentType || 'application/octet-stream',
    contentLength: response.ContentLength || 0,
  };
}

/**
 * Check if a file exists in S3.
 * @param {string} key - S3 object key (filename)
 * @returns {Promise<boolean>}
 */
async function fileExists(key) {
  try {
    const { HeadObjectCommand } = require('@aws-sdk/client-s3');
    const client = getClient();

    await client.send(new HeadObjectCommand({
      Bucket: S3_BUCKET,
      Key: `messenger-media/${key}`,
    }));
    return true;
  } catch (e) {
    if (e.name === 'NotFound' || e.$metadata?.httpStatusCode === 404) {
      return false;
    }
    throw e;
  }
}

/** @returns {boolean} Whether S3 archiving is enabled */
function isEnabled() {
  return S3_ARCHIVE_ENABLED;
}

module.exports = {
  uploadFile,
  getFileStream,
  fileExists,
  isEnabled,
  S3_BUCKET,
  S3_ENDPOINT,
};
