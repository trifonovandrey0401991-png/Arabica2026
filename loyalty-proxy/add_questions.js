const https = require('https');
const fs = require('fs');
const path = require('path');

const questionsFile = path.join(__dirname, '..', 'questions_to_add.json');
const questions = JSON.parse(fs.readFileSync(questionsFile, 'utf8'));

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
        const type = q.isYesNo ? 'да/нет' : (q.isNumberOnly ? 'число' : (q.isPhotoOnly ? 'фото' : 'текст'));
        const shortQ = q.question.length > 50 ? q.question.substring(0, 50) + '...' : q.question;
        console.log(`[${index + 1}/${questions.length}] ${res.statusCode === 201 || res.statusCode === 200 ? 'OK' : 'FAIL'} [${type}] ${shortQ}`);
        resolve(responseData);
      });
    });

    req.on('error', (e) => {
      console.error(`Error: ${e.message}`);
      reject(e);
    });

    req.write(data);
    req.end();
  });
}

async function main() {
  console.log(`Adding ${questions.length} questions...`);
  console.log('');

  for (let i = 0; i < questions.length; i++) {
    try {
      await addQuestion(questions[i], i);
    } catch (e) {
      console.log(`[${i + 1}/${questions.length}] ERROR: ${e.message}`);
    }
    // Small delay between requests
    await new Promise(r => setTimeout(r, 150));
  }

  console.log('');
  console.log('Done!');
}

main();
