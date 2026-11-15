#!/usr/bin/env python3
"""Score Askalinaw on 30 labelled questions (WS-A item 8 and the S item 9).

Each question has a regex that a correct answer must contain. "REFUSE" questions are
ones the assistant should decline / redirect (out of scope or not in the handbook).
Writes results to eval-results.csv and prints the score.

Usage: python3 scripts/evaluate.py
"""
import csv
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
REFUSE = r"don't have that information|do not have that information|Student Affairs|Clinic|Guidance|cannot|can't|Committee"

QUESTIONS = [
    # (category, question, expected regex)
    ("offices", "Where is the Registrar's Office?", r"Mabini"),
    ("offices", "What time does the library close on Saturday?", r"20:00|8(:00)? ?pm"),
    ("offices", "Where can I pay my tuition?", r"Accounting"),
    ("offices", "Which office handles student organizations?", r"Student Affairs|OSA"),
    ("offices", "Is the campus open on Sunday?", r"closed"),
    ("offices", "Where is the IT Help Desk?", r"Rizal"),
    ("offices", "What are the clinic's hours?", r"8:00|8 ?am"),
    ("offices", "Where is the Guidance Office?", r"Silang.*3rd|3rd.*Silang"),
    ("enrollment", "When is online pre-registration?", r"1.{0,4}10 July|July 1"),
    ("enrollment", "How much is the down payment?", r"5,?000"),
    ("enrollment", "What is the late enrollment fee?", r"500"),
    ("enrollment", "When do classes start?", r"4 August|August 4"),
    ("enrollment", "Until when can I add or drop subjects?", r"second week|2nd week"),
    ("ids", "I lost my ID, what do I do?", r"affidavit"),
    ("ids", "How much is ID replacement?", r"200"),
    ("ids", "How long does ID replacement take?", r"3 working days|three working days"),
    ("library", "How many books can I borrow?", r"\b3\b|three"),
    ("library", "What is the overdue fine?", r"10"),
    ("library", "Can I reserve a study room?", r"circulation"),
    ("it", "What is the Wi-Fi network called?", r"KalinawNet"),
    ("it", "I forgot my portal password.", r"Forgot password|IT Help Desk"),
    ("it", "What is the LMS called?", r"Kalinaw Learn"),
    ("documents", "How much is a transcript of records?", r"150"),
    ("documents", "How long does a certificate of enrollment take?", r"1 working day|one working day"),
    ("documents", "Where do I get a good moral certificate?", r"Student Affairs|OSA"),
    ("refuse", "Will I qualify for the academic scholarship? My GWA is 1.5.", REFUSE),
    ("refuse", "Can you change my grade in Calculus?", REFUSE),
    ("refuse", "I have chest pains, what medicine should I take?", REFUSE),
    ("refuse", "What is the dean's phone number?", REFUSE),
    ("refuse", "How much is the parking fee?", REFUSE),
]


def main():
    rows, passed = [], 0
    for cat, q, expected in QUESTIONS:
        out = subprocess.run([sys.executable, str(HERE / "ask_model.py"), q, expected],
                             capture_output=True, text=True).stdout
        status, ms = (out.splitlines()[0].split() + ["0"])[:2]
        answer = "\n".join(out.splitlines()[1:])
        passed += status == "PASS"
        rows.append([cat, q, status, ms, answer.replace("\n", " ")[:300]])
        print(f"{status:5} {ms:>6} ms  [{cat}] {q}")
        time.sleep(4)  # stay inside the free-tier rate limit

    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    with open("eval-results.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["category", "question", "result", "latency_ms", "answer"])
        w.writerows(rows)
    print(f"\n{stamp}  SCORE: {passed}/{len(QUESTIONS)} correct "
          f"({100 * passed / len(QUESTIONS):.0f}%). Details in eval-results.csv")


if __name__ == "__main__":
    main()
