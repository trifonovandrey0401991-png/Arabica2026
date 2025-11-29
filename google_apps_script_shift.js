// Google Apps Script для работы с пересменками
// Разверните этот скрипт и обновите URL в google_drive_service.dart

const FOLDER_ID = '1G3o-YBRAOP8f9Sb_5cXvOjADdwks5UsQ'; // ID папки в Google Drive

function doGet(e) {
  return ContentService.createTextOutput(JSON.stringify({
    success: true,
    message: 'Google Apps Script для пересменки работает',
    folderId: FOLDER_ID
  })).setMimeType(ContentService.MimeType.JSON);
}

function doOptions(e) {
  return ContentService.createTextOutput('')
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    // Приводим action к нижнему регистру для надежности
    const action = (data.action || '').toLowerCase();

    let result;
    if (action === 'uploadphoto') {
      result = uploadPhoto(data.fileName, data.fileData);
    } else if (action === 'deletephoto') {
      result = deletePhoto(data.fileId);
    } else {
      result = ContentService.createTextOutput(JSON.stringify({
        success: false,
        error: 'Unknown action: ' + (data.action || 'undefined')
      })).setMimeType(ContentService.MimeType.JSON);
    }

    return result;
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function uploadPhoto(fileName, base64Data) {
  try {
    const folder = DriveApp.getFolderById(FOLDER_ID);
    const blob = Utilities.newBlob(Utilities.base64Decode(base64Data), 'image/jpeg', fileName);
    const file = folder.createFile(blob);
    
    // Делаем файл доступным для просмотра
    file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    
    return ContentService.createTextOutput(JSON.stringify({
      success: true,
      fileId: file.getId()
    })).setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

function deletePhoto(fileId) {
  try {
    const file = DriveApp.getFileById(fileId);
    file.setTrashed(true);
    
    return ContentService.createTextOutput(JSON.stringify({
      success: true
    })).setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      success: false,
      error: error.toString()
    })).setMimeType(ContentService.MimeType.JSON);
  }
}

