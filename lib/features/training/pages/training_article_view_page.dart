import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/training_model.dart';
import '../models/content_block.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница просмотра статьи обучения
class TrainingArticleViewPage extends StatelessWidget {
  final TrainingArticle article;

  const TrainingArticleViewPage({super.key, required this.article});

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось открыть ссылку'),
              backgroundColor: Colors.red[600],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    }
  }

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
              _buildAppBar(context),
              Expanded(
                child: _buildContent(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          // Кнопка назад
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          // Заголовок
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (article.group.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 3.h),
                    child: Text(
                      article.group,
                      style: TextStyle(
                        color: AppColors.gold.withOpacity(0.7),
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Кнопка внешней ссылки
          if (article.hasUrl)
            Container(
              margin: EdgeInsets.only(left: 8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: IconButton(
                icon: Icon(Icons.open_in_new, color: Colors.white.withOpacity(0.7), size: 20),
                onPressed: () => _openUrl(context, article.url!),
                tooltip: 'Открыть источник',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (!article.hasContent && article.hasUrl) {
      return _buildUrlOnlyState(context);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 32.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок-карточка статьи
          _buildArticleHeader(),
          SizedBox(height: 12),
          // Контент
          if (article.hasBlocks)
            ..._buildContentBlocks(context)
          else
            _buildSimpleContent(context),
          // Ссылка на источник
          if (article.hasUrl) ...[
            SizedBox(height: 12),
            _buildSourceLink(context),
          ],
        ],
      ),
    );
  }

  /// Карточка-заголовок статьи
  Widget _buildArticleHeader() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gold.withOpacity(0.15),
            AppColors.gold.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              Icons.auto_stories_rounded,
              color: AppColors.gold,
              size: 22,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.title,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                if (article.group.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 6.h),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        article.group,
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Простой текстовый контент
  Widget _buildSimpleContent(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: article.content.isNotEmpty
          ? SelectableText(
              article.content,
              style: TextStyle(
                fontSize: 14.sp,
                height: 1.7,
                color: Colors.white.withOpacity(0.85),
              ),
            )
          : Text(
              'Контент статьи не добавлен',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.white.withOpacity(0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
    );
  }

  /// Блоки контента (текст + изображения)
  List<Widget> _buildContentBlocks(BuildContext context) {
    return article.contentBlocks.map((block) {
      if (block.type == ContentBlockType.image) {
        return _buildImageBlock(context, block);
      } else {
        return _buildTextBlock(context, block);
      }
    }).toList();
  }

  /// Блок текста
  Widget _buildTextBlock(BuildContext context, ContentBlock block) {
    if (block.content.trim().isEmpty) return SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10.h),
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: SelectableText(
        block.content,
        style: TextStyle(
          fontSize: 14.sp,
          height: 1.7,
          color: Colors.white.withOpacity(0.85),
        ),
      ),
    );
  }

  /// Блок изображения
  Widget _buildImageBlock(BuildContext context, ContentBlock block) {
    final hasCaption = block.caption != null && block.caption!.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Подпись к изображению (сверху)
          if (hasCaption)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 10.h),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.3),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14.r),
                  topRight: Radius.circular(14.r),
                ),
              ),
              child: Text(
                block.caption!,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          // Изображение с кэшированием
          ClipRRect(
            borderRadius: hasCaption
                ? BorderRadius.only(
                    bottomLeft: Radius.circular(14.r),
                    bottomRight: Radius.circular(14.r),
                  )
                : BorderRadius.circular(14.r),
            child: GestureDetector(
              onTap: () => _showFullScreenImage(context, block.content),
              child: CachedNetworkImage(
                imageUrl: block.content,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 800,
                placeholder: (context, url) => Container(
                  width: double.infinity,
                  height: 200,
                  color: AppColors.emeraldDark.withOpacity(0.5),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.gold.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: double.infinity,
                  height: 180,
                  color: AppColors.emeraldDark.withOpacity(0.3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image_rounded, color: Colors.white.withOpacity(0.3), size: 40),
                      SizedBox(height: 8),
                      Text(
                        'Ошибка загрузки',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Показать изображение в полноэкранном режиме
  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator(
                    color: AppColors.gold,
                  ),
                ),
                errorWidget: (context, url, error) => Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ссылка на внешний источник
  Widget _buildSourceLink(BuildContext context) {
    return GestureDetector(
      onTap: () => _openUrl(context, article.url!),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(Icons.link_rounded, color: Colors.white.withOpacity(0.7), size: 18),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Внешний источник',
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  Text(
                    article.url!,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.white.withOpacity(0.4),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded, color: Colors.white.withOpacity(0.4), size: 16),
          ],
        ),
      ),
    );
  }

  /// Состояние "Только ссылка"
  Widget _buildUrlOnlyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(
                Icons.link_rounded,
                size: 36,
                color: AppColors.gold.withOpacity(0.6),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Внешняя статья',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Эта статья содержит только ссылку\nна внешний источник',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.white.withOpacity(0.5),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openUrl(context, article.url!),
              icon: Icon(Icons.open_in_new_rounded),
              label: Text('Открыть источник'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold.withOpacity(0.2),
                foregroundColor: AppColors.gold,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: AppColors.gold.withOpacity(0.4)),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
