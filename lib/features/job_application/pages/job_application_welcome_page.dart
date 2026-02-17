import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'job_application_form_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class JobApplicationWelcomePage extends StatelessWidget {
  const JobApplicationWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Устроиться на работу',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
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
                    padding: EdgeInsets.all(32.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Иконка
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.12),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.gold.withOpacity(0.25), width: 2),
                          ),
                          child: Icon(
                            Icons.celebration,
                            size: 56,
                            color: AppColors.gold.withOpacity(0.9),
                          ),
                        ),
                        SizedBox(height: 40),

                        // Заголовок
                        Text(
                          'Мы Рады что вы выбрали нас!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white.withOpacity(0.95),
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 16),

                        // Подзаголовок
                        Text(
                          'Заполните пожалуйста анкету',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        SizedBox(height: 48),

                        // Кнопка "Анкета"
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => JobApplicationFormPage(),
                                ),
                              );
                            },
                            icon: Icon(Icons.description, color: AppColors.gold),
                            label: Text(
                              'Анкета',
                              style: TextStyle(fontSize: 18.sp, color: AppColors.gold),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.gold.withOpacity(0.5)),
                              padding: EdgeInsets.symmetric(vertical: 16.h),
                              backgroundColor: AppColors.gold.withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14.r),
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
