from django import forms
from .models import Report

class ReportForm(forms.ModelForm):
    class Meta:
        model = Report
        fields = [
            'report_type',
            'data',
            'cache_hit',
            'generation_time_ms',
        ]

        labels = {
            'report_type' : 'Report Type',
            'data' : 'Data',
            'cache_hit' : 'Cache Hit',
            'generation_time_ms' : 'Generation Time (ms)',
        }
