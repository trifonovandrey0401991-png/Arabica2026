import 'package:flutter/material.dart';
import 'job_application_form_page.dart';

class JobApplicationWelcomePage extends StatelessWidget {
  const JobApplicationWelcomePage({super.key});

  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Устроиться на работу',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Иконка
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.12),
                            shape: BoxShape.circle,
                            border: Border.all(color: _gold.withOpacity(0.25), width: 2),
                          ),
                          child: Icon(
                            Icons.celebration,
                            size: 56,
                            color: _gold.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Заголовок
                        Text(
                          'Мы Рады что вы выбрали нас!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.95),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Подзаголовок
                        Text(
                          'Заполните пожалуйста анкету',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Кнопка "Анкета"
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const JobApplicationFormPage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.description, color: _gold),
                            label: Text(
                              'Анкета',
                              style: TextStyle(fontSize: 18, color: _gold),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: _gold.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: _gold.withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
