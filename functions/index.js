const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();

const DAYS = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];

// ═════════════════════════════════════════════════════════════════
//  TRIGGER — Push notification for gate pass / permission / complaint
// ═════════════════════════════════════════════════════════════════
exports.sendPushOnNotification = onDocumentCreated(
  "notifications/{notifId}",
  async (event) => {
    const data = event.data.data();
    if (!data) return null;
    if (data.sent === true) return null;

    const token = data.toToken;
    const title = data.title ?? "";
    const body  = data.body  ?? "";

    if (!token || !title) {
      console.log("[Push] Missing token or title, skipping:", event.params.notifId);
      await event.data.ref.update({ sent: true, skipped: true });
      return null;
    }

    console.log(`[Push] Sending type=${data.type} to token=${token.substring(0, 20)}...`);

    const message = {
      token,
      notification: { title, body },
      data: {
        type:         data.type    ?? "",
        passId:       data.passId  ?? "",
        permId:       data.permId  ?? "",
        toUid:        data.toUid   ?? "",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: { sound: "default", channelId: "hostel_alerts" },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { sound: "default", badge: 1 } },
      },
    };

    try {
      const response = await admin.messaging().send(message);
      console.log(`[Push] ✅ Sent: ${response}`);
      await event.data.ref.update({ sent: true, sentAt: admin.firestore.FieldValue.serverTimestamp() });
    } catch (err) {
      console.error(`[Push] ❌ Failed:`, err.message);
      if (
        err.code === "messaging/registration-token-not-registered" ||
        err.code === "messaging/invalid-registration-token"
      ) {
        const uid = data.toUid;
        if (uid) {
          await admin.firestore().collection("users").doc(uid)
            .update({ fcmToken: admin.firestore.FieldValue.delete() });
          console.log(`[Push] Removed stale token for uid: ${uid}`);
        }
      }
      await event.data.ref.update({ sent: false, error: err.message });
    }

    return null;
  }
);

// ═════════════════════════════════════════════════════════════════
//  SHARED HELPER — send non-veg push to a list of tokens
// ═════════════════════════════════════════════════════════════════
async function sendNonVegMulticast(tokenMap, title, body, dayName) {
  const BATCH = 500;
  for (let i = 0; i < tokenMap.length; i += BATCH) {
    const slice  = tokenMap.slice(i, i + BATCH);
    const tokens = slice.map(x => x.token);

    const message = {
      notification: { title, body },           // ← required for killed-app display
      data: {
        type:         "mess_nonveg_reminder",
        day:          dayName,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      android: {
        priority: "high",
        notification: { sound: "default", channelId: "mess_menu_ch" },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { sound: "default", badge: 1 } },
      },
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`[NonVeg] Batch ${Math.floor(i / BATCH) + 1}: ${response.successCount}/${tokens.length} sent`);

    for (let j = 0; j < response.responses.length; j++) {
      const r = response.responses[j];
      if (!r.success &&
        (r.error?.code === "messaging/registration-token-not-registered" ||
         r.error?.code === "messaging/invalid-registration-token")) {
        await admin.firestore().collection("users").doc(slice[j].uid)
          .update({ fcmToken: admin.firestore.FieldValue.delete() });
        console.log(`[NonVeg] Removed stale token for uid: ${slice[j].uid}`);
      }
    }
  }
}

// ═════════════════════════════════════════════════════════════════
//  SHARED HELPER — fetch eligible student tokens for a hostel
//  Skips students who already have a booking for that day
// ═════════════════════════════════════════════════════════════════
async function getEligibleTokens(hostelId, dayName) {
  const [usersSnap, bookingsSnap] = await Promise.all([
    admin.firestore()
      .collection("users")
      .where("role", "==", "student")
      .where("hostelId", "==", hostelId)
      .get(),
    admin.firestore()
      .collection("messBookings")
      .where("day", "==", dayName)
      .get(),
  ]);

  const bookedUids = new Set(bookingsSnap.docs.map(d => d.data().studentUid));

  const tokenMap = [];
  usersSnap.forEach(doc => {
    if (bookedUids.has(doc.id)) return;
    const token = doc.data().fcmToken;
    if (token) tokenMap.push({ token, uid: doc.id });
  });

  return tokenMap;
}

// ═════════════════════════════════════════════════════════════════
//  SCHEDULED — Hourly non-veg reminder  9 PM → 9 AM IST
//  Fires at the top of every hour in the window (13 total slots)
// ═════════════════════════════════════════════════════════════════
exports.hourlyNonVegReminder = onSchedule(
  { schedule: "0 21-23,0-9 * * *", timeZone: "Asia/Kolkata" },
  async () => {
    const now  = new Date();
    const hour = now.getHours();

    const inWindow = hour >= 21 || hour <= 9;
    if (!inWindow) {
      console.log(`[HourlyNonVeg] Outside window (hour=${hour}), skipping.`);
      return;
    }

    // 9 PM–11 PM → non-veg meal is TOMORROW
    // 12 AM–9 AM → non-veg meal is TODAY
    const targetDate = new Date(now);
    if (hour >= 21) targetDate.setDate(targetDate.getDate() + 1);

    const yyyy    = targetDate.getFullYear();
    const mm      = String(targetDate.getMonth() + 1).padStart(2, "0");
    const dd      = String(targetDate.getDate()).padStart(2, "0");
    const docId   = `${yyyy}-${mm}-${dd}`;
    const dayName = DAYS[targetDate.getDay()];

    console.log(`[HourlyNonVeg] hour=${hour} IST, checking ${docId} (${dayName})`);

    const hostelsSnap = await admin.firestore().collection("messMenu").get();
    if (hostelsSnap.empty) {
      console.log("[HourlyNonVeg] No hostel docs found.");
      return;
    }

    for (const hostelDoc of hostelsSnap.docs) {
      const hostelId = hostelDoc.id;

      const menuSnap = await admin.firestore()
        .collection("messMenu").doc(hostelId)
        .collection("daily").doc(docId)
        .get();

      if (!menuSnap.exists || !menuSnap.data()?.hasNonVeg) {
        console.log(`[HourlyNonVeg] No non-veg for hostel ${hostelId} on ${docId}`);
        continue;
      }

      const menuData = menuSnap.data();
      const allItems = (menuData.nonVegItems || []).join(", ");
      const title    = "🍗 Non-Veg Tomorrow – Book Now!";
      const body     = allItems
        ? `${allItems} available tomorrow (${dayName}) — book before 9 AM!`
        : `Non-veg available tomorrow (${dayName}) — book before 9 AM!`;

      const tokenMap = await getEligibleTokens(hostelId, dayName);

      if (tokenMap.length === 0) {
        console.log(`[HourlyNonVeg] No eligible students for hostel ${hostelId}`);
        continue;
      }

      console.log(`[HourlyNonVeg] Sending to ${tokenMap.length} students (hostel: ${hostelId})`);
      await sendNonVegMulticast(tokenMap, title, body, dayName);
    }
  }
);

// ═════════════════════════════════════════════════════════════════
//  TRIGGER — Firestore: fires when warden updates the menu doc
//  Sends an immediate push when non-veg items are added/changed
// ═════════════════════════════════════════════════════════════════
exports.onMenuUpdatedNotify = onDocumentWritten(
  "messMenu/{hostelId}/daily/{dateId}",
  async (event) => {
    const before = event.data.before.data() ?? {};
    const after  = event.data.after.data();

    if (!after || !event.data.after.exists) return;

    const wasNonVeg    = before.hasNonVeg === true;
    const isNonVeg     = after.hasNonVeg  === true;
    const itemsBefore  = JSON.stringify(before.nonVegItems ?? []);
    const itemsAfter   = JSON.stringify(after.nonVegItems  ?? []);
    const itemsChanged = itemsBefore !== itemsAfter;

    if (!isNonVeg) {
      console.log("[MenuUpdate] No non-veg in updated doc, skipping.");
      return;
    }

    if (wasNonVeg && !itemsChanged) {
      console.log("[MenuUpdate] Non-veg unchanged, skipping duplicate notify.");
      return;
    }

    const hostelId = event.params.hostelId;
    const allItems = (after.nonVegItems || []).join(", ");
    const dayName  = after.day || event.params.dateId;
    const title    = "🍗 Non-Veg Added to Menu!";
    const body     = allItems
      ? `${allItems} added for ${dayName} — book before 9 AM!`
      : `Non-veg added for ${dayName} — book before 9 AM!`;

    console.log(`[MenuUpdate] Non-veg updated for hostel ${hostelId}, day ${dayName}`);

    const tokenMap = await getEligibleTokens(hostelId, dayName);
    if (tokenMap.length === 0) {
      console.log(`[MenuUpdate] No eligible students for hostel ${hostelId}`);
      return;
    }

    await sendNonVegMulticast(tokenMap, title, body, dayName);
  }
);