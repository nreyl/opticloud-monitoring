from django.urls import path
from . import views

urlpatterns = [
    path('reports/<str:report_type>/', views.report_view),
    path('reports/cache-stats/', views.cache_stats_view),
]
