import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
class MediaDetailsPage extends StatelessWidget {
 const MediaDetailsPage({required this.item,required this.searchService,required this.preferences,this.playerFactory,super.key});
 final MediaItem item; final MediaSearchService searchService; final UserPreferences preferences; final MediaPlayerFactory? playerFactory;
 @override Widget build(BuildContext context)=>Scaffold(backgroundColor:SystemCorePalette.background,appBar:AppBar(title:const Text('О ФИЛЬМЕ'),backgroundColor:SystemCorePalette.panel),body:FutureBuilder<MediaDetails?>(future:searchService.loadDetails(item),builder:(context,s){
  final d=s.data; final overview=d?.overview.isNotEmpty==true?d!.overview:item.description; final genres=d?.genres??item.categories;
  return ListView(padding:const EdgeInsets.all(18),children:[
   if(d?.backdropUrl.isNotEmpty==true) ClipRRect(borderRadius:BorderRadius.circular(14),child:Image.network(d!.backdropUrl,height:180,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox.shrink())),
   const SizedBox(height:12),Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    if(item.posterUrl.isNotEmpty) ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.network(item.posterUrl,width:112,height:166,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox.shrink())),
    const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text(item.title,style:const TextStyle(color:Colors.white,fontSize:23,fontWeight:FontWeight.bold)),const SizedBox(height:8),
     Text(item.type,style:const TextStyle(color:SystemCorePalette.muted)),const SizedBox(height:8),
     Text('★ ${item.rating.toStringAsFixed(1)}',style:const TextStyle(color:SystemCorePalette.green,fontWeight:FontWeight.bold)),
     if(d?.releaseDate.isNotEmpty==true) Text(d!.releaseDate,style:const TextStyle(color:Colors.white70)),
     if(d?.runtimeMinutes!=null) Text('${d!.runtimeMinutes} мин.',style:const TextStyle(color:Colors.white70)),
    ]))]),
   const SizedBox(height:20),const _Label('ОПИСАНИЕ'),const SizedBox(height:8),Text(overview.isEmpty?'Описание пока недоступно.':overview,style:const TextStyle(color:Colors.white70,height:1.5)),
   const SizedBox(height:20),const _Label('ЖАНРЫ'),const SizedBox(height:8),
   Wrap(spacing:8,children:genres.map((g)=>Chip(label:Text(g),backgroundColor:SystemCorePalette.panel,labelStyle:const TextStyle(color:Colors.white),side:BorderSide(color:SystemCorePalette.green.withValues(alpha:.4)))).toList()),
   const SizedBox(height:20),const _Label('АКТЁРСКИЙ СОСТАВ'),const SizedBox(height:8),
   if(s.connectionState==ConnectionState.waiting&&d==null) const Center(child:CircularProgressIndicator()),
   if(d!=null) SizedBox(height:170,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:d.cast.length,separatorBuilder:(_,__)=>const SizedBox(width:10),itemBuilder:(context,i){final a=d.cast[i];return SizedBox(width:100,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    if(a.photoUrl.isEmpty) Container(width:100,height:110,color:SystemCorePalette.panel,child:const Icon(Icons.person,color:SystemCorePalette.muted)) else Image.network(a.photoUrl,width:100,height:110,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(width:100,height:110,color:SystemCorePalette.panel,child:const Icon(Icons.person,color:SystemCorePalette.muted))),
    const SizedBox(height:5),Text(a.name,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.bold)),Text(a.character,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:SystemCorePalette.muted,fontSize:10))
   ]));}),
   if(d!=null&&d.cast.isEmpty) const Text('Информация об актёрах недоступна.',style:TextStyle(color:Colors.white70)),
   const SizedBox(height:20),
   if(item.videoUrl.isNotEmpty) FilledButton.icon(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>PlayerPage(item:item,preferences:preferences,searchService:searchService,playerFactory:playerFactory))),icon:const Icon(Icons.play_arrow),label:const Text('СМОТРЕТЬ'))
   else OutlinedButton.icon(onPressed:d?.homepage.isNotEmpty==true?()=>launchUrl(Uri.parse(d!.homepage),mode:LaunchMode.externalApplication):null,icon:const Icon(Icons.open_in_new),label:const Text('ОФИЦИАЛЬНАЯ СТРАНИЦА')),
   const SizedBox(height:12),const Text('This product uses the TMDB API but is not endorsed or certified by TMDB.',style:TextStyle(color:SystemCorePalette.muted,fontSize:10)),
  ]);}));
}
class _Label extends StatelessWidget {const _Label(this.value);final String value;@override Widget build(BuildContext context)=>Text(value,style:const TextStyle(color:SystemCorePalette.green,fontSize:11,letterSpacing:1,fontWeight:FontWeight.bold));}
