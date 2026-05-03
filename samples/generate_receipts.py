"""
Generate sample receipt images for testing OncoGlobal_ParseReceiptImage.
Outputs PNG files into samples/ alongside this script.
"""
from PIL import Image, ImageDraw, ImageFont
import os

OUT_DIR = os.path.dirname(os.path.abspath(__file__))


def font(size, bold=False):
    candidates = [
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()


def line(draw, y, w, color=(180, 180, 180)):
    draw.line([(20, y), (w - 20, y)], fill=color, width=1)


def receipt_ola(path):
    W, H = 600, 820
    img = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, W, 80], fill=(20, 30, 40))
    d.text((30, 24), "Ola", font=font(38, bold=True), fill=(255, 220, 50))
    d.text((110, 32), "Trip Receipt", font=font(20), fill=(220, 220, 220))

    d.text((30, 110), "Customer: Sanket Zambare", font=font(18), fill=(40, 40, 40))
    d.text((30, 140), "Date: 03 May 2026", font=font(18), fill=(40, 40, 40))
    d.text((30, 170), "Booking ID: CRN1234567890", font=font(16), fill=(80, 80, 80))
    d.text((30, 195), "Driver: Ramesh K. | Vehicle: MH-04-AB-1234", font=font(14), fill=(100, 100, 100))

    line(d, 230, W)
    d.text((30, 245), "Trip Details", font=font(20, bold=True), fill=(20, 30, 40))
    d.text((30, 280), "From: Apollo Hospital, Bandra West", font=font(15), fill=(60, 60, 60))
    d.text((30, 305), "To: Onco Global HQ, BKC", font=font(15), fill=(60, 60, 60))
    d.text((30, 335), "Distance: 7.4 km    Duration: 28 min", font=font(15), fill=(60, 60, 60))
    d.text((30, 360), "Trip Type: Mini", font=font(15), fill=(60, 60, 60))

    line(d, 400, W)
    d.text((30, 415), "Fare Breakup", font=font(20, bold=True), fill=(20, 30, 40))
    rows = [
        ("Base fare", "75.00"),
        ("Distance charge (7.4 km)", "210.00"),
        ("Time charge (28 min)", "56.00"),
        ("Booking fee", "20.00"),
        ("CGST @ 2.5%", "9.03"),
        ("SGST @ 2.5%", "9.03"),
    ]
    y = 450
    for label, amt in rows:
        d.text((30, y), label, font=font(15), fill=(60, 60, 60))
        d.text((W - 30, y), f"INR {amt}", font=font(15), fill=(60, 60, 60), anchor="rt")
        y += 28

    line(d, y + 4, W, color=(60, 60, 60))
    d.text((30, y + 18), "Total Paid", font=font(22, bold=True), fill=(20, 30, 40))
    d.text((W - 30, y + 18), "INR 379.06", font=font(22, bold=True), fill=(20, 100, 30), anchor="rt")

    d.text((30, H - 60), "Payment: UPI - HDFC Bank •••• 4521", font=font(13), fill=(110, 110, 110))
    d.text((30, H - 40), "Thank you for riding with Ola.", font=font(13), fill=(110, 110, 110))

    img.save(path)
    return path


def receipt_taj_cafe(path):
    W, H = 540, 760
    img = Image.new("RGB", (W, H), (252, 250, 244))
    d = ImageDraw.Draw(img)

    d.text((W // 2, 30), "TAJ CAFE", font=font(36, bold=True), fill=(70, 30, 10), anchor="mt")
    d.text((W // 2, 80), "Linking Road, Bandra West, Mumbai", font=font(13), fill=(100, 80, 60), anchor="mt")
    d.text((W // 2, 102), "GSTIN: 27AABCT1234B1Z5", font=font(12), fill=(120, 100, 80), anchor="mt")

    line(d, 135, W, color=(200, 180, 150))

    d.text((30, 152), "Bill No: 0042/2026", font=font(14), fill=(70, 50, 30))
    d.text((W - 30, 152), "Date: 03/05/2026 13:42", font=font(14), fill=(70, 50, 30), anchor="rt")
    d.text((30, 178), "Server: Anil    Table: 12    Covers: 2", font=font(13), fill=(110, 90, 70))

    line(d, 215, W, color=(200, 180, 150))

    d.text((30, 230), "Item", font=font(15, bold=True), fill=(50, 30, 10))
    d.text((W - 30, 230), "Amount", font=font(15, bold=True), fill=(50, 30, 10), anchor="rt")
    line(d, 255, W, color=(220, 200, 170))

    items = [
        ("2 x Masala Chai", "120.00"),
        ("1 x Veg Thali", "320.00"),
        ("1 x Paneer Tikka", "280.00"),
        ("1 x Gulab Jamun (2 pc)", "90.00"),
        ("2 x Mineral Water (1L)", "60.00"),
    ]
    y = 270
    for label, amt in items:
        d.text((30, y), label, font=font(15), fill=(60, 40, 20))
        d.text((W - 30, y), amt, font=font(15), fill=(60, 40, 20), anchor="rt")
        y += 30

    line(d, y + 8, W, color=(220, 200, 170))
    y += 20

    sub_rows = [
        ("Subtotal", "870.00"),
        ("CGST @ 2.5%", "21.75"),
        ("SGST @ 2.5%", "21.75"),
        ("Service charge 10%", "87.00"),
    ]
    for label, amt in sub_rows:
        d.text((30, y), label, font=font(14), fill=(80, 60, 40))
        d.text((W - 30, y), amt, font=font(14), fill=(80, 60, 40), anchor="rt")
        y += 25

    line(d, y + 6, W, color=(60, 30, 10))
    y += 18
    d.text((30, y), "TOTAL", font=font(22, bold=True), fill=(70, 30, 10))
    d.text((W - 30, y), "INR 1000.50", font=font(22, bold=True), fill=(70, 30, 10), anchor="rt")

    y += 60
    d.text((30, y), "Paid by: Card ending 4521 (Visa)", font=font(13), fill=(110, 90, 70))
    d.text((30, y + 22), "Authorisation: 084573", font=font(13), fill=(110, 90, 70))

    d.text((W // 2, H - 30), "Thank you. Visit again!", font=font(15), fill=(70, 30, 10), anchor="mt")

    img.save(path)
    return path


if __name__ == "__main__":
    p1 = receipt_ola(os.path.join(OUT_DIR, "receipt_ola_cab.png"))
    p2 = receipt_taj_cafe(os.path.join(OUT_DIR, "receipt_taj_cafe.png"))
    print("Wrote:")
    print(" -", p1)
    print(" -", p2)
