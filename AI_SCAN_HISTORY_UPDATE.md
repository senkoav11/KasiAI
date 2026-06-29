# AI Scan History Update

Updated AI Crop Doctor history behavior:

- Shows 10 AI scan history records per page.
- Adds pagination when history has more than 10 records.
- Keeps only the latest 20 AI scan records per user.
- Automatically deletes older records beyond the latest 20 from Firestore.
- Local fallback history also keeps only the latest 20 records.

Version: 1.0.7+8
