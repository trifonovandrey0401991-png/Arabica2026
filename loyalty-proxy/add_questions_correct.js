const https = require('https');
const fs = require('fs');

const questions = JSON.parse(fs.readFileSync('/root/arabica_app/questions_correct.json', 'utf8'));

async function addQuestion(q, index) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(q);

    const options = {
      hostname: 'arabica26.ru',
      port: 443,
      path: '/api/shift-questions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': Buffer.byteLength(data, 'utf8')
      }
    };

    const req = https.request(options, (res) => {
      let responseData = '';
      res.on('data', (chunk) => responseData += chunk);
      res.on('end', () => {
        let type = 'да/нет';
        if (q.answerFormatB === 'photo') type = 'фото';
        else if (q.answerFormatB === 'text') type = 'текст';
        else if (q.answerFormatC === 'число') type = 'число';

        const shortQ = q.question.length > 45 ? q.question.substring(0, 45) + '...' : q.question;
        console.log('[' + (index + 1) + '/' + questions.length + '] ' + (res.statusCode < 300 ? 'OK' : 'FAIL') + ' [' + type + '] ' + shortQ);
        resolve(responseData);
      });
    });

    req.on('error', (e) => {
      console.error('Error: ' + e.message);
      reject(e);
    });

    req.write(data);
    req.end();
  });
}

async function main() {
  console.log('Adding ' + questions.length + ' questions with correct format...');
  console.log('');

  for (let i = 0; i < questions.length; i++) {
    try {
      await addQuestion(questions[i], i);
    } catch (e) {
      console.log('[' + (i + 1) + '/' + questions.length + '] ERROR: ' + e.message);
    }
    await new Promise(r => setTimeout(r, 100));
  }

  console.log('');
  console.log('Done!');
}

main();
