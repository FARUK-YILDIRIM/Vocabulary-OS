# On-device insight evaluation

- Date: Oct 4, 2026 at 1:23 AM
- System: macOS Version 26.5.2 (Build 25F84), Apple on-device model (stepwise strategy)
- Command: `swift run --package-path Packages/VocabularyKit vos-eval insight`
- Result: right sense 10/10, right translation 9/10, valid 10/10, median latency 1.58 s (targets: ≥ 8/10 senses, all valid, median < 3 s — met)

| Term | Sentence | Sense | Translation | Native entry | Seconds |
| --- | --- | --- | --- | --- | --- |
| cookies | This website uses cookies for tracking. | ✓ small pieces of data stored on a user's computer to remember preferences and track activity. | ✓ | Çerez — Bir kullanıcının bilgisayarında tercihlerini hatırlamak ve aktivitelerini izlemek için saklanan küçük veri parçaları. | 2.4 |
| cookie | She dipped a chocolate chip cookie in her milk. | ✓ A small, sweet baked food. | ✗ | Çerez — Tatlı ve küçük, fırında pişirilmiş bir yiyecek. | 1.4 |
| Bank | Wir saßen auf einer Bank im Park. | ✓ a seat for two or more people. | ✓ | bank — Birden fazla kişinin oturabileceği iki veya daha fazla sandalyeden oluşan bir platform veya alan. | 1.7 |
| Bank | Ich muss zur Bank, um Geld abzuheben. | ✓ a financial institution that provides services such as savings accounts, loans, and currency exchange | ✓ | Banka — Para biriktirme, kredi alma ve döviz değişimi gibi hizmetler sunan finansal kurum. | 2.0 |
| pitch | She gave a great pitch to the investors. | ✓ a persuasive speech or presentation. | ✓ | Sunum — Bir konuşma veya sunumun etkili ve ikna edici olması. | 1.5 |
| pitch | The football pitch was wet after the rain. | ✓ a flat area of land where a game of football is played. | ✓ | Sahaya — Futbol oynanan düz bir arazi alanı. | 1.4 |
| ran | He ran the family company for ten years. | ✓ to operate a business or organization. | ✓ | işletme yönetimi — Bir işletmeyi veya kuruluşu yönetmek, işletmeyi yürütmek. | 1.6 |
| raining cats and dogs | Take an umbrella, it's raining cats and dogs. | ✓ It is raining very heavily. | ✓ | Yağmur çok şiddetli — Yağmur çok şiddetli, yağmur damlaları büyük ve yoğun bir şekilde düşüyor. | 1.6 |
| abzuheben | Ich muss zur Bank, um Geld abzuheben. | ✓ to take money out of a bank account | ✓ | withdraw — to take money out of a bank account | 0.9 |
| Schlüssel | Ich habe meinen Schlüssel im Büro vergessen. | ✓ a metal object with a hole for a keyring, used to open doors. | ✓ | Anahtar — Kapılara açılan metal bir nesne. | 1.6 |
