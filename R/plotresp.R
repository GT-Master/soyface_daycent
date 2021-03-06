#!/usr/bin/env Rscript

library(ggplot2)
library(DeLuciatoR) # https://github.com/infotroph/DeLuciatoR
library(ggplotTicks) # https://github.com/infotroph/ggplotTicks

lm_eqn = function(mod){
	eq <- substitute(italic(y) == a + b %.% italic(x)*","~~italic(R)^2~"="~r2,
		list(a = format(coef(mod)[1], digits = 2),
			b = format(coef(mod)[2], digits = 2),
			r2 = format(summary(mod)$r.squared, digits = 2)))
	as.character(as.expression(eq))
}

resp = read.csv(
	"../validation_data/soyface-2009to2011-soilresp.csv",
	colClasses=c(
		Season="factor",
		Component="factor",
		Heat="factor",
		CO2="factor",
		Day="Date",
		lsmean="numeric",
		SE="numeric",
		df="numeric",
		lower.CL="numeric",
		upper.CL="numeric"
		))

resp$Treatment = paste0(resp$Heat, resp$CO2)
resp$Date = resp$Day

# If argv exists already, we're being sourced from inside another script.
# If not, we're running standalone and taking arguments from the command line.
if(!exists("argv")){
	argv = commandArgs(trailingOnly = TRUE)
}

mresp = read.csv(paste0(argv[1], "_mresp.csv"), check.names=FALSE)
gresp = read.csv(paste0(argv[1], "_gresp.csv"), check.names=FALSE)
sysc = read.csv(paste0(argv[1], "_sysc.csv"), check.names=FALSE)

rows_wanted = (mresp$time >= 2009 & mresp$time < 2012)
mresp = mresp[rows_wanted,]
gresp = gresp[rows_wanted,]
sysc = sysc[rows_wanted,]

scaleflux = function(x){
	return(x
	/12 # g C/mol
	/86400 # sec/day
	*1e6) # µmol/mol
}

dcresp = data.frame(
	run=mresp$run,
	time=mresp$time,
	dayofyr=mresp$dayofyr,
	mleaf=scaleflux(mresp$"cmrspflux(1)"),
	mroot=scaleflux(mresp$"cmrspflux(2)" + mresp$"cmrspflux(3)"))
 dcresp$gleaf = scaleflux(gresp$"cgrspflux(1)")
 dcresp$groot = scaleflux(gresp$"cgrspflux(2)" + gresp$"cgrspflux(3)")
 dcresp$hetresp = scaleflux(sysc$CO2resp)

 rm(list=c("mresp", "gresp", "sysc"))

dcresp$Date = as.Date(
	paste(floor(dcresp$time), dcresp$dayofyr),
	format="%Y %j")
dcresp$Heat = factor(ifelse(
		dcresp$run %in% c("heat", "heatco2"),
		"h",
		"c"))
dcresp$CO2 = factor(ifelse(
	dcresp$run %in% c("co2", "heatco2"),
	"Elevated",
	"Ambient"))

# Why yes, I AM going from a four-level factor to two
# two-level factors back to a new four-level factor.
# Perhaps foolishly, I think this is the easiest way
# to get matching Treatment names between simulated and observed datasets
# without worrying about factor level ordering.
dcresp$Treatment = paste0(dcresp$Heat, dcresp$CO2)

dcresp_aut = dcresp
dcresp_aut$Component = "Raut"
dcresp_aut$lsmean = dcresp$mroot + dcresp$groot

dcresp_het = dcresp
dcresp_het$Component = "Rhet"
dcresp_het$lsmean = dcresp$hetresp

dcresp_tot = dcresp
dcresp_tot$Component = "Rtot"
dcresp_tot$lsmean = dcresp$hetresp + dcresp$mroot + dcresp$groot

dcresp_long=rbind(dcresp_aut, dcresp_het,dcresp_tot)

componentexpr = data.frame(
	Component.txt=c("Rhet", "Raut", "Rtot"),
	Component.expr=c("R[het]","R[aut]","R[tot]"))
dcresp_long = merge(dcresp_long, componentexpr, by.x="Component", by.y="Component.txt")
resp = merge(resp, componentexpr, by.x="Component", by.y="Component.txt")

scale_labels = c(
	cAmbient="Control",
	hAmbient="Heat",
	cElevated=expression(CO[2]),
	hElevated=expression(paste("Heat+", CO[2])))

panel_txt = data.frame(
	Date=max(resp$Date),
	lsmean=tapply(resp$lsmean+resp$SE, resp$Component, max)[c("Rhet", "Raut", "Rtot")],
	Treatment="hAmbient",
	Component.expr=c("R[het]", "R[aut]", "R[tot]"),
	label=c("(b)", "(a)", "(c)")) # beware! manual sorting!

pltl=(ggplot(data=dcresp_long,
		aes(Date, lsmean, color=Treatment, shape=Treatment, lty=Treatment))
	+facet_grid(
		Component.expr~.,
		labeller=label_parsed,
		scales="free_y")
	+geom_line()
	+geom_point(
		data=resp,
		aes(x=Date, y=lsmean))
	+geom_errorbar(
		data=resp,
		aes(x=Date, y=lsmean, ymin=lsmean-SE, ymax=lsmean+SE),
		alpha=0.95,
		lty=1,
		show.legend=FALSE)
	+geom_text(
		data=panel_txt,
		aes(label=label),
		size=6,
		fontface="bold",
		nudge_x=-20,
		nudge_y=-0.5,
		show.legend=FALSE)
	+xlim(range(resp$Date))
	+scale_color_manual(
		labels=scale_labels,
		values=c(cAmbient="grey", hAmbient="black", cElevated="grey", hElevated="black"))
	+scale_shape_manual(
		labels=scale_labels,
		values=c(cAmbient=1, hAmbient=1, cElevated=17, hElevated=17))
	+scale_linetype_manual(
		labels=scale_labels,
		values=c(cAmbient=1, hAmbient=1, cElevated=2, hElevated=2))
	+theme_ggEHD(16)
	+theme(
		aspect.ratio=0.5,
		legend.position=c(0.5,0.72),
		legend.title=element_blank(),
		legend.key=element_blank(),
		legend.key.width=unit(1.5, "lines"),
		legend.key.height=unit(1, "lines"),
		legend.background=element_blank(),
		legend.text.align=0,
		strip.background=element_blank())
	+guides(col=guide_legend(ncol=2))
	+labs(
		y=expression(paste("Soil ", CO[2],  " efflux, µmol ", m^{-2}, " ", sec^{-1}))))

ggsave_fitmax(
	plot=mirror_ticks(pltl),
	filename=paste(argv[1], "_resp_vs_dc.png", sep=""),
	maxwidth=6.5,
	maxheight=9,
	units="in",
	dpi=300)



resp_comb = merge(
	x=resp,
	y=dcresp_long,
	by=c("Component", "Heat", "CO2", "Date", "Treatment", "Component.expr"),
	all.x=TRUE,
	all.y=FALSE)


lmRaut = lm(lsmean.y ~ lsmean.x, resp_comb[resp_comb$Component=="Raut",])
lmRhet = lm(lsmean.y ~ lsmean.x, resp_comb[resp_comb$Component=="Rhet",])
lmRtot = lm(lsmean.y ~ lsmean.x, resp_comb[resp_comb$Component=="Rtot",])

lm_txt = data.frame(
	Treatment="cAmbient",
	lsmean.x=0,
	lsmean.y=max(resp_comb$lsmean.y),
	Component.expr=c("R[het]", "R[aut]", "R[tot]"),
	eqn=c(lm_eqn(lmRaut), lm_eqn(lmRhet), lm_eqn(lmRtot)))

plt_lm = (ggplot(resp_comb,
			aes(x=lsmean.x, y=lsmean.y, color=Treatment))
	+ theme_ggEHD(8)
	+ geom_point()
	+ geom_smooth(method="lm")
	+ facet_grid(
		Component.expr~.,
		labeller=label_parsed)
	+ coord_equal()
	+ theme(aspect.ratio=1)
	+ geom_abline(intercept=0, slope=1)
	+ labs(
		y=expression(paste(
			"DayCent Soil ", CO[2],  " efflux, µmol ",
			m^{-2}, " ", sec^{-1})),
		x=expression(paste(
			"Measured Soil ", CO[2],  " efflux, µmol ",
			m^{-2}, " ", sec^{-1})))
	+ geom_text(
		data=lm_txt,
		mapping=aes(label=eqn),
		parse=TRUE,
		show.legend=FALSE,
		size=theme_ggEHD(8)$text$size / .pt))

ggsave_fitmax(
	plot=mirror_ticks(plt_lm),
	filename=paste(argv[1], "_resp_vs_dc_lm.png", sep=""),
	maxwidth=6.5,
	maxheight=9,
	units="in",
	dpi=300)
