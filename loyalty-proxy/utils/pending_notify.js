const fsp=require('fs').promises;
const path=require('path');
const https=require('https');
const{fileExists}=require('./file_helpers');
const DATA_DIR=process.env.DATA_DIR||'/var/www';
let _notified=false;
function _getToken(){try{return require('../admin-bot/ecosystem.config.js').apps[0].env.BOT_TOKEN;}catch{return null;}}
function _getChatId(){try{return require('../admin-bot/ecosystem.config.js').apps[0].env.ADMIN_ID;}catch{return null;}}
function notifyTelegram(text){
  try{
    const token=process.env.TELEGRAM_BOT_TOKEN||_getToken();
    const chatId=process.env.TELEGRAM_ADMIN_ID||_getChatId();
    if(!token||!chatId)return;
    const body=JSON.stringify({chat_id:chatId,text,parse_mode:'HTML'});
    const req=https.request({hostname:'api.telegram.org',
      path:`/bot${token}/sendMessage`,method:'POST',
      headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)}});
    req.on('error',()=>{});req.write(body);req.end();
  }catch{}
}
async function checkAndNotifyPending(){
  if(_notified)return;
  try{
    const f=path.join(DATA_DIR,'counting-pending','samples.json');
    if(!(await fileExists(f)))return;
    const data=JSON.parse(await fsp.readFile(f,'utf8'));
    const n=Array.isArray(data)?data.length:0;
    if(n>=50){
      _notified=true;
      notifyTelegram('🤖 <b>ИИ готов к обучению</b>\n\nНакоплено <b>'+n+' фото</b>.\nОдобрите в дашборде → «Запустить обучение».');
      console.log('[PendingNotify] '+n+' samples >= 50, notified');
    }
  }catch{}
}
function resetNotification(){_notified=false;}
module.exports={checkAndNotifyPending,resetNotification};
