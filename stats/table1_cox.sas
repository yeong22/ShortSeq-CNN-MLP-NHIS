/* Table 1, events and person-years by category, Cox models (Table 2, Table S8),
   correlation and VIF checks.
   Choi et al., BMC Med Inform Decis Mak 2026;26:44. Written for SAS 9.4.

   Input: cohort.csv from `python main.py --step build` (one row per person).
   Set the two paths below before running. */

%let workdir = /path/to/sas_library;
%let cohort  = /path/to/data/processed/cohort.csv;

libname a "&workdir";

proc import
datafile="&cohort"
out= a.liver_data
dbms=csv replace;
getnames=yes;
run;


/** short variable names used in the models below **/
/** liver_data_v1 **/
data a.liver_data_v1; set a.liver_data(rename=(
income_t1 = income_1
income_t2 = income_2
income_t3 = income_3
alcohol_t1 = drink_1
alcohol_t2 = drink_2
alcohol_t3 = drink_3
smoking_t1 = smoke_1
smoking_t2 = smoke_2
smoking_t3 = smoke_3
activity_t1 = pa_1
activity_t2 = pa_2
activity_t3 = pa_3
bmi_t1 = bmi_1
bmi_t2 = bmi_2
bmi_t3 = bmi_3
hemoglobin_t1 = hgb_1
hemoglobin_t2 = hgb_2
hemoglobin_t3 = hgb_3
glucose_t1 = fbs_1
glucose_t2 = fbs_2
glucose_t3 = fbs_3
total_chol_t1 = chol_1
total_chol_t2 = chol_2
total_chol_t3 = chol_3
waist_t1 = wstc_1
waist_t2 = wstc_2
waist_t3 = wstc_3
hdl_t1 = hdl_1
hdl_t2 = hdl_2
hdl_t3 = hdl_3
heart_disease = heart
hypertension = hyper
dyslipidemia = lipid
hbv = hbc
cryptogenic = crypto
family_liver_cancer = family_liver
family_other_cancer = family_other
fu_years = fu
alcohol_dpd_t1 = drink_p_1yr
alcohol_dpd_t2 = drink_p_2yr
alcohol_dpd_t3 = drink_p_3yr
activity_dpw_t1 = pa_p_1yr
activity_dpw_t2 = pa_p_2yr
activity_dpw_t3 = pa_p_3yr
));
run;

/** shift 0-based categories so they start at 1 **/
/* liver_data_v2 */
data a.liver_data_v2; set a.liver_data_v1;
drink_1 = drink_1 + 1;
drink_2 = drink_2 + 1;
drink_3 = drink_3 + 1;
pa_1 = pa_1 + 1;
pa_2 = pa_2 + 1;
pa_3 = pa_3 + 1;
run;

/** temporal variable mean for cox regression covariates **/
/** liver_data_v3 **/
data a.liver_data_v3; set a.liver_data_v2;
income = (income_1+income_2+income_3)/3;
run;

data a.liver_data_v3; set a.liver_data_v3;
drink_mean=((drink_p_1yr+drink_p_2yr+drink_p_3yr)/3);
run;

data a.liver_data_v3; set a.liver_data_v3;
if drink_mean = 0 then drink=1;
if 0<drink_mean<=1 then drink=2;
if 1<drink_mean<=2 then drink=3;
if 2<drink_mean<=4 then drink=4;
if 4<drink_mean<=99999 then drink=5;
run;

data a.liver_data_v3; set a.liver_data_v3;
pa_mean=((pa_p_1yr+pa_p_2yr+pa_p_3yr)/3);
run;

data a.liver_data_v3; set a.liver_data_v3;
if pa_mean = 0 then pa=1;
if 0<pa_mean<=2 then pa=2;
if 2<pa_mean<=4 then pa=3;
if pa_mean>4 then pa=4;
run;

data a.liver_data_v3; set a.liver_data_v3;
bmi = (bmi_1 + bmi_2 + bmi_3)/3;
hgb = (hgb_1 + hgb_2 + hgb_3)/3;
fbs = (fbs_1 + fbs_2 + fbs_3)/3;
chol = (chol_1 + chol_2 + chol_3)/3;
wstc = (wstc_1 + wstc_2 + wstc_3)/3;
hdl = (hdl_1 + hdl_2 + hdl_3)/3;
run;

/**useless variable drop **/
/*liver_data_v4*/
data a.liver_data_v4; set a.liver_data_v3(
drop=drink_mean pa_mean drink_p_1yr drink_p_2yr drink_p_3yr pa_p_1yr pa_p_2yr pa_p_3yr); 
run;

/** create categorical variable **/
/*final*/
data a.final; set a.liver_data_v4;

/** age **/
if age>=60 then age_g = 2; else age_g = 1;

/** bmi **/
if bmi_1>=24 then bmi_1g = 2; else bmi_1g=1;
if bmi_2>=24 then bmi_2g = 2; else bmi_2g=1;
if bmi_3>=24 then bmi_3g = 2; else bmi_3g=1;

/** hgb **/
/* first examination period */
if hgb_1<13 then hgb_1g = 1; 
else if 13 <= hgb_1 <17 then hgb_1g=2;
else if hgb_1 >=17 then hgb_1g = 3;

/* second examination period */
if hgb_2<13 then hgb_2g = 1; 
else if 13 <= hgb_2 <17 then hgb_2g=2;
else if hgb_2 >=17 then hgb_2g = 3;

/* third examination period */
if hgb_3<13 then hgb_3g = 1; 
else if 13 <= hgb_3 <17 then hgb_3g=2;
else if hgb_3 >=17 then hgb_3g = 3;

/** fbs **/
/* first examination period */
if fbs_1<100 then fbs_1g = 1; 
else if 100 <= fbs_1 <126 then fbs_1g=2;
else if fbs_1 >=126 then fbs_1g = 3;

/* second examination period */
if fbs_2<100 then fbs_2g = 1; 
else if 100 <= fbs_2 <126 then fbs_2g=2;
else if fbs_2 >=126 then fbs_2g = 3;

/* third examination period */
if fbs_3<100 then fbs_3g = 1; 
else if 100 <= fbs_3 <126 then fbs_3g=2;
else if fbs_3 >=126 then fbs_3g = 3;


/** chol **/
/* first examination period */
if chol_1<180 then chol_1g = 1; 
else if 180 <= chol_1 <240 then chol_1g=2;
else if chol_1 >=240 then chol_1g = 3;

/* second examination period */
if chol_2<180 then chol_2g = 1; 
else if 180 <= chol_2 <240 then chol_2g=2;
else if chol_2 >=240 then chol_2g = 3;

/* third examination period */
if chol_3<180 then chol_3g = 1; 
else if 180 <= chol_3 <240 then chol_3g=2;
else if chol_3 >=240 then chol_3g = 3;


/** hdl **/
/* first examination period */
if hdl_1<35 then hdl_1g = 1; 
else if 35 <= hdl_1 <60 then hdl_1g=2;
else if hdl_1 >=60 then hdl_1g = 3;

/* second examination period */
if hdl_2<35 then hdl_2g = 1; 
else if 35 <= hdl_2 <60 then hdl_2g=2;
else if hdl_2 >=60 then hdl_2g = 3;

/* third examination period */
if hdl_3<35 then hdl_3g = 1; 
else if 35 <= hdl_3 <60 then hdl_3g=2;
else if hdl_3 >=60 then hdl_3g = 3;

/** wstc **/
if wstc_1>=80 then wstc_1g = 2; else wstc_1g=1;
if wstc_2>=80 then wstc_2g = 2; else wstc_2g=1;
if wstc_3>=80 then wstc_3g = 2; else wstc_3g=1;


/** drink **/
if drink_1>=2 then drink_1g = 2; else drink_1g=1;
if drink_2>=2 then drink_2g = 2; else drink_2g=1;
if drink_3>=2 then drink_3g = 2; else drink_3g=1;

/** smoke **/
if smoke_1>=2 then smoke_1g = 2; else smoke_1g=1;
if smoke_2>=2 then smoke_2g = 2; else smoke_2g=1;
if smoke_3>=2 then smoke_3g = 2; else smoke_3g=1;

/** pa **/
if pa_1>=2 then pa_1g = 2; else pa_1g=1;
if pa_2>=2 then pa_2g = 2; else pa_2g=1;
if pa_3>=2 then pa_3g = 2; else pa_3g=1;

run;








/*****table 1*****/
/*n*/
proc freq data=a.final; table liver_label; run;

/*age*/
proc means data=a.final; var age; run;
proc means data=a.final; var age; where liver_label=0; run;
proc means data=a.final; var age; where liver_label=1; run;

/*sex*/
proc freq data=a.final; table sex*liver_label; run;

/*income*/
proc freq data=a.final; table income_1*liver_label; run;
proc freq data=a.final; table income_2*liver_label; run;
proc freq data=a.final; table income_3*liver_label; run;

/*alcohol consumption status*/
proc freq data=a.final; table drink_1*liver_label; run;
proc freq data=a.final; table drink_2*liver_label; run;
proc freq data=a.final; table drink_3*liver_label; run;

/*smoking status*/
proc freq data=a.final; table smoke_1*liver_label; run;
proc freq data=a.final; table smoke_2*liver_label; run;
proc freq data=a.final; table smoke_3*liver_label; run;

/*physical activity*/
proc freq data=a.final; table pa_1*liver_label; run;
proc freq data=a.final; table pa_2*liver_label; run;
proc freq data=a.final; table pa_3*liver_label; run;

/*bmi*/
proc means data=a.final; var bmi_1; run;
proc means data=a.final; var bmi_1; where liver_label=0; run;
proc means data=a.final; var bmi_1; where liver_label=1; run;

proc means data=a.final; var bmi_2; run;
proc means data=a.final; var bmi_2; where liver_label=0; run;
proc means data=a.final; var bmi_2; where liver_label=1; run;

proc means data=a.final; var bmi_3; run;
proc means data=a.final; var bmi_3; where liver_label=0; run;
proc means data=a.final; var bmi_3; where liver_label=1; run;


/*hgb*/
proc means data=a.final; var hgb_1; run;
proc means data=a.final; var hgb_1; where liver_label=0; run;
proc means data=a.final; var hgb_1; where liver_label=1; run;

proc means data=a.final; var hgb_2; run;
proc means data=a.final; var hgb_2; where liver_label=0; run;
proc means data=a.final; var hgb_2; where liver_label=1; run;

proc means data=a.final; var hgb_3; run;
proc means data=a.final; var hgb_3; where liver_label=0; run;
proc means data=a.final; var hgb_3; where liver_label=1; run;

/*fbs*/
proc means data=a.final; var fbs_1; run;
proc means data=a.final; var fbs_1; where liver_label=0; run;
proc means data=a.final; var fbs_1; where liver_label=1; run;

proc means data=a.final; var fbs_2; run;
proc means data=a.final; var fbs_2; where liver_label=0; run;
proc means data=a.final; var fbs_2; where liver_label=1; run;

proc means data=a.final; var fbs_3; run;
proc means data=a.final; var fbs_3; where liver_label=0; run;
proc means data=a.final; var fbs_3; where liver_label=1; run;

/*total cholesterol*/
proc means data=a.final; var chol_1; run;
proc means data=a.final; var chol_1; where liver_label=0; run;
proc means data=a.final; var chol_1; where liver_label=1; run;

proc means data=a.final; var chol_2; run;
proc means data=a.final; var chol_2; where liver_label=0; run;
proc means data=a.final; var chol_2; where liver_label=1; run;

proc means data=a.final; var chol_3; run;
proc means data=a.final; var chol_3; where liver_label=0; run;
proc means data=a.final; var chol_3; where liver_label=1; run;

/*HDL-cholesterol*/
proc means data=a.final; var hdl_1; run;
proc means data=a.final; var hdl_1; where liver_label=0; run;
proc means data=a.final; var hdl_1; where liver_label=1; run;

proc means data=a.final; var hdl_2; run;
proc means data=a.final; var hdl_2; where liver_label=0; run;
proc means data=a.final; var hdl_2; where liver_label=1; run;

proc means data=a.final; var hdl_3; run;
proc means data=a.final; var hdl_3; where liver_label=0; run;
proc means data=a.final; var hdl_3; where liver_label=1; run;

/*waist circumference*/
proc means data=a.final; var wstc_1; run;
proc means data=a.final; var wstc_1; where liver_label=0; run;
proc means data=a.final; var wstc_1; where liver_label=1; run;

proc means data=a.final; var wstc_2; run;
proc means data=a.final; var wstc_2; where liver_label=0; run;
proc means data=a.final; var wstc_2; where liver_label=1; run;

proc means data=a.final; var wstc_3; run;
proc means data=a.final; var wstc_3; where liver_label=0; run;
proc means data=a.final; var wstc_3; where liver_label=1; run;

/*history of stroke*/
proc freq data=a.final; table stroke*liver_label; run;

/*history of heart disease*/
proc freq data=a.final; table heart*liver_label; run;

/*history of hyptertension*/
proc freq data=a.final; table hyper*liver_label; run;

/*history of diabetes*/
proc freq data=a.final; table diabetes*liver_label; run;

/*history of lipid*/
proc freq data=a.final; table lipid*liver_label; run;

/*history of hcv*/
proc freq data=a.final; table hcv*liver_label; run;

/*history of hbc*/
proc freq data=a.final; table hbc*liver_label; run;

/*history of ald*/
proc freq data=a.final; table ald*liver_label; run;

/*history of masld*/
proc freq data=a.final; table masld*liver_label; run;

/*history of crypto*/
proc freq data=a.final; table crypto*liver_label; run;

/*history of cirrhosis*/
proc freq data=a.final; table cirrhosis*liver_label; run;

/*family history of liver cancer*/
proc freq data=a.final; table family_liver*liver_label; run;

/*family history of other cancer*/
proc freq data=a.final; table family_other*liver_label; run;

/** cox regression **/
/** unadjusted, fully adjusted, and collinearity-based adjusted models **/

/** age **/
proc sort data=a.final; by age_g; run;

proc freq data=a.final; table liver_label*age_g; run;
proc univariate data=a.final; var fu; by age_g; run;

/* unadjusted */
proc phreg data=a.final; class age_g (param=reference ref="1") ;
model fu*liver_label(0) = age_g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class age_g (param=reference ref="1") sex (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = age_g sex income drink pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/*collinearity-based adjusted*/
proc phreg data=a.final; class age_g (param=reference ref="1") sex (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = age_g sex income drink pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/** sex **/
proc sort data=a.final; by sex; run;

proc freq data=a.final; table liver_label*sex; run;
proc univariate data=a.final; var fu; by sex; run;

/* unadjusted */
proc phreg data=a.final; class sex (param=reference ref="1") ;
model fu*liver_label(0) = sex  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class sex (param=reference ref="1") drink(param=reference ref="1") income(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = sex age income drink pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class sex (param=reference ref="1") drink(param=reference ref="1") income(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = sex age income drink pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/** income **/

/* first examination period */
proc sort data=a.final; by income_1; run;

proc freq data=a.final; table liver_label*income_1; run;
proc univariate data=a.final; var fu; by income_1; run;

/* unadjusted */
proc phreg data=a.final; class income_1 (param=reference ref="1") ;
model fu*liver_label(0) = income_1  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class income_1(param=reference ref="1") sex (param=reference ref="1") drink(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = income_1 sex age drink pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class income_1(param=reference ref="1") sex (param=reference ref="1") drink(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = income_1 sex age drink pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* second examination period */
proc sort data=a.final; by income_2; run;

proc freq data=a.final; table liver_label*income_2; run;
proc univariate data=a.final; var fu; by income_2; run;

/* unadjusted */
proc phreg data=a.final; class income_2 (param=reference ref="1") ;
model fu*liver_label(0) = income_2  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class income_2(param=reference ref="1") sex (param=reference ref="1") drink(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = income_2 sex age drink pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class income_2(param=reference ref="1") sex (param=reference ref="1") drink(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = income_2 sex age drink pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* third examination period */
proc sort data=a.final; by income_3; run;

proc freq data=a.final; table liver_label*income_3; run;
proc univariate data=a.final; var fu; by income_3; run;

/* unadjusted */
proc phreg data=a.final; class income_3 (param=reference ref="1") ;
model fu*liver_label(0) = income_3  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class income_3(param=reference ref="1") sex (param=reference ref="1") drink(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = income_3 sex age drink pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class income_3(param=reference ref="1") sex (param=reference ref="1") drink(param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = income_3 sex age drink pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** alcohol consumption **/

/* first examination period */
proc sort data=a.final; by drink_1; run;

proc freq data=a.final; table liver_label*drink_1; run;
proc univariate data=a.final; var fu; by drink_1; run;

/* unadjusted */
proc phreg data=a.final; class drink_1 (param=reference ref="1") ;
model fu*liver_label(0) = drink_1  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class drink_1 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = drink_1 sex age income pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;


/* collinearity-based adjusted */
proc phreg data=a.final; class drink_1 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = drink_1 sex age income pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/* second examination period */
proc sort data=a.final; by drink_2; run;

proc freq data=a.final; table liver_label*drink_2; run;
proc univariate data=a.final; var fu; by drink_2; run;

/* unadjusted */
proc phreg data=a.final; class drink_2 (param=reference ref="1") ;
model fu*liver_label(0) = drink_2  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class drink_2 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = drink_2 age sex income pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class drink_2 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = drink_2 sex age income pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/* third examination period */
proc sort data=a.final; by drink_3; run;

proc freq data=a.final; table liver_label*drink_3; run;
proc univariate data=a.final; var fu; by drink_3; run;

/* unadjusted */
proc phreg data=a.final; class drink_3 (param=reference ref="1") ;
model fu*liver_label(0) = drink_3  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class drink_3 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = drink_3 age sex income pa smoke_3 bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class drink_3 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = drink_3 sex age income pa smoke_3 bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;



/** smoking status **/

/* first examination period */
proc sort data=a.final; by smoke_1; run;

proc freq data=a.final; table liver_label*smoke_1; run;
proc univariate data=a.final; var fu; by smoke_1; run;

/* unadjusted */
proc phreg data=a.final; class smoke_1 (param=reference ref="1") ;
model fu*liver_label(0) = smoke_1  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class smoke_1 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = smoke_1 sex age income pa drink bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class smoke_1 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = smoke_1 sex age income pa drink bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/* second examination period */
proc sort data=a.final; by smoke_2; run;

proc freq data=a.final; table liver_label*smoke_2; run;
proc univariate data=a.final; var fu; by smoke_2; run;

/* unadjusted */
proc phreg data=a.final; class smoke_2 (param=reference ref="1") ;
model fu*liver_label(0) = smoke_2  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class smoke_2 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = smoke_2 sex age income pa drink bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class smoke_2 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = smoke_2 sex age income pa drink bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* third examination period */
proc sort data=a.final; by smoke_3; run;

proc freq data=a.final; table liver_label*smoke_3; run;
proc univariate data=a.final; var fu; by smoke_3; run;

/* unadjusted */
proc phreg data=a.final; class smoke_3 (param=reference ref="1") ;
model fu*liver_label(0) = smoke_3  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class smoke_3 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = smoke_3 sex age income pa drink bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class smoke_3 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = smoke_3 sex age income pa drink bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/** physical activity **/

/* first examination period */
proc sort data=a.final; by pa_1; run;

proc freq data=a.final; table liver_label*pa_1; run;
proc univariate data=a.final; var fu; by pa_1; run;

/* unadjusted */
proc phreg data=a.final; class pa_1 (param=reference ref="1") ;
model fu*liver_label(0) = pa_1  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class pa_1 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = pa_1 sex age income smoke_3 drink bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class pa_1 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = pa_1 sex age income smoke_3 drink bmi hgb fbs hdl stroke heart hyper  hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/* second examination period */
proc sort data=a.final; by pa_2; run;

proc freq data=a.final; table liver_label*pa_2; run;
proc univariate data=a.final; var fu; by pa_2; run;

/* unadjusted */
proc phreg data=a.final; class pa_2 (param=reference ref="1") ;
model fu*liver_label(0) = pa_2  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class pa_2 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = pa_2 sex age income smoke_3 drink bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class pa_2 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = pa_2 sex age income smoke_3 drink bmi hgb fbs hdl stroke heart hyper  hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/* third examination period */
proc sort data=a.final; by pa_3; run;

proc freq data=a.final; table liver_label*pa_3; run;
proc univariate data=a.final; var fu; by pa_3; run;

/* unadjusted */
proc phreg data=a.final; class pa_3 (param=reference ref="1") ;
model fu*liver_label(0) = pa_3  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class pa_3 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = pa_3 sex age income smoke_3 drink bmi hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class pa_3 (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = pa_3 sex age income smoke_3 drink bmi hgb fbs hdl stroke heart hyper  hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** BMI **/

/* first examination period */
proc sort data=a.final; by bmi_1g; run;

proc freq data=a.final; table liver_label*bmi_1g; run;
proc univariate data=a.final; var fu; by bmi_1g; run;

/* unadjusted */
proc phreg data=a.final; class bmi_1g (param=reference ref="1") ;
model fu*liver_label(0) = bmi_1g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class bmi_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = bmi_1g sex age income smoke_3 drink pa hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class bmi_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = bmi_1g sex age income smoke_3 drink pa hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;



/* second examination period */
proc sort data=a.final; by bmi_2g; run;

proc freq data=a.final; table liver_label*bmi_2g; run;
proc univariate data=a.final; var fu; by bmi_2g; run;

/* unadjusted */
proc phreg data=a.final; class bmi_2g (param=reference ref="1") ;
model fu*liver_label(0) = bmi_2g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class bmi_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = bmi_2g sex age income smoke_3 drink pa hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class bmi_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = bmi_2g sex age income smoke_3 drink pa hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* third examination period */
proc sort data=a.final; by bmi_3g; run;

proc freq data=a.final; table liver_label*bmi_3g; run;
proc univariate data=a.final; var fu; by bmi_3g; run;

/* unadjusted */
proc phreg data=a.final; class bmi_3g (param=reference ref="1") ;
model fu*liver_label(0) = bmi_3g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class bmi_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = bmi_3g sex age income smoke_3 drink pa hgb fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class bmi_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = bmi_3g sex age income smoke_3 drink pa hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;



/** HGB **/

/* first examination period */
proc sort data=a.final; by hgb_1g; run;

proc freq data=a.final; table liver_label*hgb_1g; run;
proc univariate data=a.final; var fu; by hgb_1g; run;

/* unadjusted */
proc phreg data=a.final; class hgb_1g (param=reference ref="1") ;
model fu*liver_label(0) = hgb_1g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hgb_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hgb_1g sex age income smoke_3 drink pa bmi fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hgb_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hgb_1g sex age income smoke_3 drink pa bmi fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/* second examination period */
proc sort data=a.final; by hgb_2g; run;

proc freq data=a.final; table liver_label*hgb_2g; run;
proc univariate data=a.final; var fu; by hgb_2g; run;

/* unadjusted */
proc phreg data=a.final; class hgb_2g (param=reference ref="1") ;
model fu*liver_label(0) = hgb_2g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hgb_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hgb_2g sex age income smoke_3 drink pa bmi fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hgb_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hgb_2g sex age income smoke_3 drink pa bmi fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/* third examination period */
proc sort data=a.final; by hgb_3g; run;

proc freq data=a.final; table liver_label*hgb_3g; run;
proc univariate data=a.final; var fu; by hgb_3g; run;

/* unadjusted */
proc phreg data=a.final; class hgb_3g (param=reference ref="1") ;
model fu*liver_label(0) = hgb_3g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hgb_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hgb_3g sex age income smoke_3 drink pa bmi fbs chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hgb_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hgb_3g sex age income smoke_3 drink pa bmi fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** FBS **/

/* first examination period */
proc sort data=a.final; by fbs_1g; run;

proc freq data=a.final; table liver_label*fbs_1g; run;
proc univariate data=a.final; var fu; by fbs_1g; run;

/* unadjusted */
proc phreg data=a.final; class fbs_1g (param=reference ref="1") ;
model fu*liver_label(0) = fbs_1g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class fbs_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = fbs_1g sex age income smoke_3 drink pa bmi hgb chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class fbs_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = fbs_1g sex age income smoke_3 drink pa bmi hgb hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* second examination period */
proc sort data=a.final; by fbs_2g; run;

proc freq data=a.final; table liver_label*fbs_2g; run;
proc univariate data=a.final; var fu; by fbs_2g; run;

/* unadjusted */
proc phreg data=a.final; class fbs_2g (param=reference ref="1") ;
model fu*liver_label(0) = fbs_2g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class fbs_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = fbs_2g sex age income smoke_3 drink pa bmi hgb chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class fbs_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = fbs_2g sex age income smoke_3 drink pa bmi hgb hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* third examination period */
proc sort data=a.final; by fbs_3g; run;

proc freq data=a.final; table liver_label*fbs_3g; run;
proc univariate data=a.final; var fu; by fbs_3g; run;

/* unadjusted */
proc phreg data=a.final; class fbs_3g (param=reference ref="1") ;
model fu*liver_label(0) = fbs_3g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class fbs_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = fbs_3g sex age income smoke_3 drink pa bmi hgb chol wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class fbs_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = fbs_3g sex age income smoke_3 drink pa bmi hgb hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** WSTC **/

/* first examination period */
proc sort data=a.final; by wstc_1g; run;

proc freq data=a.final; table liver_label*wstc_1g; run;
proc univariate data=a.final; var fu; by wstc_1g; run;

/* unadjusted */
proc phreg data=a.final; class wstc_1g (param=reference ref="1") ;
model fu*liver_label(0) = wstc_1g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class wstc_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = wstc_1g sex age income smoke_3 drink pa bmi hgb fbs chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class wstc_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = wstc_1g sex age income smoke_3 drink pa hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* second examination period */
proc sort data=a.final; by wstc_2g; run;

proc freq data=a.final; table liver_label*wstc_2g; run;
proc univariate data=a.final; var fu; by wstc_2g; run;

/* unadjusted */
proc phreg data=a.final; class wstc_2g (param=reference ref="1") ;
model fu*liver_label(0) = wstc_2g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class wstc_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = wstc_2g sex age income smoke_3 drink pa bmi hgb fbs chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class wstc_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = wstc_2g sex age income smoke_3 drink pa hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;



/* third examination period */
proc sort data=a.final; by wstc_3g; run;

proc freq data=a.final; table liver_label*wstc_3g; run;
proc univariate data=a.final; var fu; by wstc_3g; run;

/* unadjusted */
proc phreg data=a.final; class wstc_3g (param=reference ref="1") ;
model fu*liver_label(0) = wstc_3g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class wstc_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = wstc_3g sex age income smoke_3 drink pa bmi hgb fbs chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class wstc_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = wstc_3g sex age income smoke_3 drink pa hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** total cholsterol **/

/* first examination period */
proc sort data=a.final; by chol_1g; run;

proc freq data=a.final; table liver_label*chol_1g; run;
proc univariate data=a.final; var fu; by chol_1g; run;

/* unadjusted */
proc phreg data=a.final; class chol_1g (param=reference ref="1") ;
model fu*liver_label(0) = chol_1g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class chol_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = chol_1g sex age income smoke_3 drink pa bmi hgb fbs wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class chol_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = chol_1g sex age income smoke_3 drink pa bmi hgb fbs stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/* second examination period */
proc sort data=a.final; by chol_2g; run;

proc freq data=a.final; table liver_label*chol_2g; run;
proc univariate data=a.final; var fu; by chol_2g; run;

/* unadjusted */
proc phreg data=a.final; class chol_2g (param=reference ref="1") ;
model fu*liver_label(0) = chol_2g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class chol_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = chol_2g sex age income smoke_3 drink pa bmi hgb fbs wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class chol_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = chol_2g sex age income smoke_3 drink pa bmi hgb fbs stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;



/* third examination period */
proc sort data=a.final; by chol_3g; run;

proc freq data=a.final; table liver_label*chol_3g; run;
proc univariate data=a.final; var fu; by chol_3g; run;

/* unadjusted */
proc phreg data=a.final; class chol_3g (param=reference ref="1") ;
model fu*liver_label(0) = chol_3g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class chol_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = chol_3g sex age income smoke_3 drink pa bmi hgb fbs wstc hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class chol_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = chol_3g sex age income smoke_3 drink pa bmi hgb fbs stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/** hdl-cholsterol **/

/* first examination period */
proc sort data=a.final; by hdl_1g; run;

proc freq data=a.final; table liver_label*hdl_1g; run;
proc univariate data=a.final; var fu; by hdl_1g; run;

/* unadjusted */
proc phreg data=a.final; class hdl_1g (param=reference ref="1") ;
model fu*liver_label(0) = hdl_1g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hdl_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hdl_1g sex age income smoke_3 drink pa bmi hgb fbs wstc chol stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hdl_1g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hdl_1g sex age income smoke_3 drink pa bmi hgb fbs stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/*second examination period */
proc sort data=a.final; by hdl_2g; run;

proc freq data=a.final; table liver_label*hdl_2g; run;
proc univariate data=a.final; var fu; by hdl_2g; run;

/* unadjusted */
proc phreg data=a.final; class hdl_2g (param=reference ref="1") ;
model fu*liver_label(0) = hdl_2g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hdl_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hdl_2g sex age income smoke_3 drink pa bmi hgb fbs wstc chol stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hdl_2g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hdl_2g sex age income smoke_3 drink pa bmi hgb fbs stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;

/*third examination period */
proc sort data=a.final; by hdl_3g; run;

proc freq data=a.final; table liver_label*hdl_3g; run;
proc univariate data=a.final; var fu; by hdl_3g; run;

/* unadjusted */
proc phreg data=a.final; class hdl_3g (param=reference ref="1") ;
model fu*liver_label(0) = hdl_3g  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class  hdl_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hdl_3g sex age income smoke_3 drink pa bmi hgb fbs wstc chol stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hdl_3g (param=reference ref="1") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hdl_3g sex age income smoke_3 drink pa bmi hgb fbs stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** history of stroke **/

proc sort data=a.final; by stroke; run;

proc freq data=a.final; table liver_label*stroke; run;
proc univariate data=a.final; var fu; by stroke; run;

/* unadjusted */
proc phreg data=a.final; class stroke (param=reference ref="0") ;
model fu*liver_label(0) = stroke  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class stroke (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = stroke sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class stroke (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = stroke sex age income smoke_3 drink pa bmi hgb fbs hdl heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** history of heart disease **/

proc sort data=a.final; by heart; run;

proc freq data=a.final; table liver_label*heart; run;
proc univariate data=a.final; var fu; by heart; run;

/* unadjusted */
proc phreg data=a.final; class heart (param=reference ref="0") ;
model fu*liver_label(0) = heart  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class heart (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = heart sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class heart (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = heart sex age income smoke_3 drink pa bmi hgb fbs hdl stroke hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** history of hypertension **/

proc sort data=a.final; by hyper; run;

proc freq data=a.final; table liver_label*hyper; run;
proc univariate data=a.final; var fu; by hyper; run;

/* unadjusted */
proc phreg data=a.final; class hyper (param=reference ref="0") ;
model fu*liver_label(0) = hyper  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hyper (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hyper sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hyper (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hyper sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** history of diabetes **/

proc sort data=a.final; by diabetes; run;

proc freq data=a.final; table liver_label*diabetes; run;
proc univariate data=a.final; var fu; by diabetes; run;

/* unadjusted */
proc phreg data=a.final; class diabetes (param=reference ref="0") ;
model fu*liver_label(0) = diabetes  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class diabetes (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = diabetes sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class diabetes (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = diabetes sex age income smoke_3 drink pa bmi hgb hdl stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** history of lipid **/

proc sort data=a.final; by lipid; run;

proc freq data=a.final; table liver_label*lipid; run;
proc univariate data=a.final; var fu; by lipid; run;

/* unadjusted */
proc phreg data=a.final; class lipid (param=reference ref="0") ;
model fu*liver_label(0) = lipid  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class lipid (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = lipid sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes hcv hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class lipid (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = lipid sex age income smoke_3 drink pa bmi hgb fbs stroke heart hyper hcv hbc masld cirrhosis family_liver family_other / risklimits; 
run;



/** history of hcv **/

proc sort data=a.final; by hcv; run;

proc freq data=a.final; table liver_label*hcv; run;
proc univariate data=a.final; var fu; by hcv; run;

/* unadjusted */
proc phreg data=a.final; class hcv (param=reference ref="0") ;
model fu*liver_label(0) = hcv  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hcv (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hcv sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hbc ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hcv (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0")  masld (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hcv sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hbc masld cirrhosis family_liver family_other / risklimits; 
run;


/** history of hbc **/

proc sort data=a.final; by hbc; run;

proc freq data=a.final; table liver_label*hbc; run;
proc univariate data=a.final; var fu; by hbc; run;

/* unadjusted */
proc phreg data=a.final; class hbc (param=reference ref="0") ;
model fu*liver_label(0) = hbc  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class hbc (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hbc sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv ald masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class hbc (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = hbc sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hcv masld cirrhosis family_liver family_other / risklimits; 
run;


/** history of ald **/

proc sort data=a.final; by ald; run;

proc freq data=a.final; table liver_label*ald; run;
proc univariate data=a.final; var fu; by ald; run;

/* unadjusted */
proc phreg data=a.final; class ald (param=reference ref="0") ;
model fu*liver_label(0) = ald  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class ald (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = ald sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv hbc masld crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class ald (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = ald sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hcv hbc cirrhosis family_liver family_other / risklimits; 
run;



/** history of masld **/

proc sort data=a.final; by masld; run;

proc freq data=a.final; table liver_label*masld; run;
proc univariate data=a.final; var fu; by masld; run;

/* unadjusted */
proc phreg data=a.final; class masld (param=reference ref="0") ;
model fu*liver_label(0) = masld  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class masld (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = masld sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv hbc ald crypto cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class masld (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = masld sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hcv hbc cirrhosis family_liver family_other / risklimits; 
run;


/** history of crypto **/

proc sort data=a.final; by crypto; run;

proc freq data=a.final; table liver_label*crypto; run;
proc univariate data=a.final; var fu; by crypto; run;

/* unadjusted */
proc phreg data=a.final; class crypto (param=reference ref="0") ;
model fu*liver_label(0) = crypto  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class crypto (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = crypto sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld cirrhosis family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class crypto (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = crypto sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hcv hbc cirrhosis family_liver family_other / risklimits; 
run;



/** history of cirrhosis **/

proc sort data=a.final; by cirrhosis; run;

proc freq data=a.final; table liver_label*cirrhosis; run;
proc univariate data=a.final; var fu; by cirrhosis; run;

/* unadjusted */
proc phreg data=a.final; class cirrhosis (param=reference ref="0") ;
model fu*liver_label(0) = cirrhosis  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class cirrhosis (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = cirrhosis sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto family_liver family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class cirrhosis (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = cirrhosis sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hcv hbc masld family_liver family_other / risklimits; 
run;


/** family history of liver cancer **/

proc sort data=a.final; by family_liver; run;

proc freq data=a.final; table liver_label*family_liver; run;
proc univariate data=a.final; var fu; by family_liver; run;

/* unadjusted */
proc phreg data=a.final; class family_liver (param=reference ref="0") ;
model fu*liver_label(0) = family_liver  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class family_liver (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = family_liver sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_other / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class family_liver (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = family_liver sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_other / risklimits; 
run;


/** family history of cancer other than liver cancer**/

proc sort data=a.final; by family_other; run;

proc freq data=a.final; table liver_label*family_other; run;
proc univariate data=a.final; var fu; by family_other; run;

/* unadjusted */
proc phreg data=a.final; class family_other (param=reference ref="0") ;
model fu*liver_label(0) = family_other  / risklimits; 
run;

/* adjusted */
proc phreg data=a.final; class family_other (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = family_other sex age income smoke_3 drink pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver / risklimits; 
run;

/* collinearity-based adjusted */
proc phreg data=a.final; class family_other (param=reference ref="0") sex (param=reference ref="1") income (param=reference ref="1") drink (param=reference ref="1") smoke_3 (param=reference ref="1") pa (param=reference ref="1") stroke (param=reference ref="0") heart (param=reference ref="0") hyper (param=reference ref="0") diabetes (param=reference ref="0") lipid (param=reference ref="0") hcv (param=reference ref="0") hbc(param=reference ref="0") ald (param=reference ref="0") masld (param=reference ref="0") crypto (param=reference ref="0") cirrhosis (param=reference ref="0") family_liver(param=reference ref="0") family_other (param=reference ref="0") ;
model fu*liver_label(0) = family_other sex age income smoke_3 drink pa bmi hgb fbs hdl stroke heart hyper hcv hbc masld cirrhosis family_liver / risklimits; 
run;






/* correlation check */
proc corr data=a.final nosimple plots=matrix(histogram); 
var age income bmi hgb fbs wstc chol hdl; 
run;

/* vif check */

data reg_dummy; set a.final; dummy_y=1; run;

proc reg data=reg_dummy;
model dummy_y = age sex income drink smoke_3 pa bmi hgb fbs wstc chol hdl stroke heart hyper diabetes lipid hcv hbc ald masld crypto cirrhosis family_liver family_other / vif;
run;
quit;
