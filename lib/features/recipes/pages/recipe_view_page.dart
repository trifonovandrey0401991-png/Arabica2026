import 'package:flutter/material.dart';
import '../models/recipe_model.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class RecipeViewPage extends StatelessWidget {
  final Recipe recipe;

  const RecipeViewPage({
    super.key,
    required this.recipe,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        backgroundColor: AppColors.primaryGreen,
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Фото
              if (recipe.photoUrlOrId != null)
                Card(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: recipe.photoUrlOrId!.startsWith('http')
                        ? AppCachedImage(
                            imageUrl: recipe.photoUrlOrId!,
                            height: 300,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Image.asset(
                              'assets/images/no_photo.png',
                              height: 300,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Image.asset(
                            'assets/images/${recipe.photoId}.jpg',
                            height: 300,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/no_photo.png',
                              height: 300,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),
              SizedBox(height: 16),
              // Цена
              if (recipe.price != null && recipe.price!.isNotEmpty)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Цена',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${recipe.price} руб.',
                          style: TextStyle(
                            fontSize: 24.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (recipe.price != null && recipe.price!.isNotEmpty)
                SizedBox(height: 16),
              // Ингредиенты
              if (recipe.ingredients.isNotEmpty)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ингредиенты',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          recipe.ingredients.replaceAll('\\n', '\n'),
                          style: TextStyle(fontSize: 16.sp),
                        ),
                      ],
                    ),
                  ),
                ),
              if (recipe.ingredients.isNotEmpty) SizedBox(height: 16),
              // Последовательность приготовления
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Последовательность приготовления',
                        style: TextStyle(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        recipe.steps.isNotEmpty
                            ? recipe.steps.replaceAll('\\n', '\n')
                            : recipe.recipeText.replaceAll('\\n', '\n'),
                        style: TextStyle(fontSize: 16.sp),
                      ),
                    ],
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
