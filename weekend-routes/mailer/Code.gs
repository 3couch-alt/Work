/**
 * SCCOL Weekend Routes: Gmail sender.
 *
 * The route board's database sends this script a small message for each
 * email (supervisor alerts, approval notices, reminders). The script sends
 * it from your Gmail. Free Gmail accounts can send about 100 a day.
 *
 * One-time setup (easiest on a computer):
 *  1. Go to https://script.google.com and click "New project".
 *  2. Delete what's in the editor, paste this whole file, and put your
 *     sender key on the KEY line below. Click the save icon.
 *  3. Click Deploy > New deployment. Click the gear next to "Select type"
 *     and choose "Web app". Set "Execute as" to Me and "Who has access" to
 *     Anyone. Click Deploy.
 *  4. Click "Authorize access" and choose your Google account. If Google
 *     says it hasn't verified the app, click Advanced, then "Go to ...
 *     (unsafe)", then Allow. It's your own script, and it can only send
 *     email as you.
 *  5. Copy the Web app URL (it ends in /exec). Paste it on the board's
 *     manager page under Email, then press "Send a test email".
 */

const KEY = 'PASTE-YOUR-SENDER-KEY-HERE';
const FROM_NAME = 'SCCOL Weekend Routes';

function doPost(e) {
  let data;
  try {
    data = JSON.parse(e.postData.contents);
  } catch (err) {
    return reply({ ok: false, error: 'The message was not JSON.' });
  }
  if (data.token !== KEY) {
    return reply({ ok: false, error: 'Wrong sender key.' });
  }

  const to = String(data.to || '').trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) {
    return reply({ ok: false, error: 'Bad email address.' });
  }

  const options = { name: String(data.fromName || FROM_NAME) };
  if (data.replyTo) options.replyTo = String(data.replyTo);

  try {
    MailApp.sendEmail(to, String(data.subject || '').slice(0, 250), String(data.text || ''), options);
  } catch (err) {
    return reply({ ok: false, error: String(err && err.message || err) });
  }
  return reply({ ok: true, left_today: MailApp.getRemainingDailyQuota() });
}

// Opening the link in a browser shows this, so you can tell it's running.
function doGet() {
  return reply({ ok: true, service: 'SCCOL Weekend Routes email sender' });
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
