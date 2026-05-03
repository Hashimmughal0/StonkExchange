import React, { useEffect, useRef, useState } from 'react';
import { motion, useScroll, useTransform } from 'framer-motion';

// Load all images from the prop directory via Vite's import.meta.glob
const imageModules = import.meta.glob('../../../prop/*.jpg', { eager: true, as: 'url' });

// Sort the URLs so they are in sequential order (001, 002... 240)
const imageUrls = Object.keys(imageModules)
  .sort()
  .map((key) => imageModules[key]);

export default function HomePage() {
  const containerRef = useRef(null);

  // Track scroll progress within the 600vh container
  const { scrollYProgress } = useScroll({
    target: containerRef,
    offset: ["start start", "end end"]
  });

  const canvasRef = useRef(null);
  const frameCount = imageUrls.length || 240;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || imageUrls.length === 0) return;
    const ctx = canvas.getContext('2d');

    // Preload images
    const loadedImages = [];
    let imagesLoaded = 0;

    for (let i = 0; i < frameCount; i++) {
      const img = new Image();
      img.src = imageUrls[i];
      img.onload = () => {
        imagesLoaded++;
        if (imagesLoaded === 1) {
          // Draw first frame once loaded
          renderFrame(0);
        }
      };
      loadedImages.push(img);
    }

    const renderFrame = (index) => {
      if (!ctx || !canvas || !loadedImages[index]) return;
      const img = loadedImages[index];

      // Clear canvas
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      // Calculate aspect ratio to cover canvas
      const canvasRatio = canvas.width / canvas.height;
      const imgRatio = img.width / img.height;

      let drawWidth, drawHeight, offsetX, offsetY;

      if (canvasRatio > imgRatio) {
        drawWidth = canvas.width;
        drawHeight = canvas.width / imgRatio;
        offsetX = 0;
        offsetY = (canvas.height - drawHeight) / 2;
      } else {
        drawHeight = canvas.height;
        drawWidth = canvas.height * imgRatio;
        offsetX = (canvas.width - drawWidth) / 2;
        offsetY = 0;
      }

      ctx.drawImage(img, offsetX, offsetY, drawWidth, drawHeight);
    };

    const unsubscribe = scrollYProgress.onChange((val) => {
      const frameIndex = Math.min(
        frameCount - 1,
        Math.floor(val * frameCount)
      );
      requestAnimationFrame(() => renderFrame(frameIndex));
    });

    // Resize handler
    const resize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
      renderFrame(Math.floor(scrollYProgress.get() * frameCount));
    };
    window.addEventListener('resize', resize);
    resize();

    return () => {
      unsubscribe();
      window.removeEventListener('resize', resize);
    };
  }, [scrollYProgress, frameCount]);

  // Storytelling scroll sections mapping based on prompt
  // 0-15%: Hero
  // 15-40%: Engineering Reveal
  // 40-65%: Insights
  // 65-80%: Security
  // 80-95%: Reassembly / CTA
  // 95-100%: Creators

  const heroOpacity = useTransform(scrollYProgress, [0, 0.05, 0.1], [1, 1, 0]);
  const heroY = useTransform(scrollYProgress, [0, 0.1], [0, -100]);
  const heroDisplay = useTransform(scrollYProgress, (v) => v > 0.12 ? "none" : "flex");

  const engOpacity = useTransform(scrollYProgress, [0.15, 0.20, 0.30, 0.35], [0, 1, 1, 0]);
  const engY = useTransform(scrollYProgress, [0.15, 0.20, 0.35], [50, 0, -50]);
  const engDisplay = useTransform(scrollYProgress, (v) => v < 0.12 || v > 0.38 ? "none" : "flex");

  const noiseOpacity = useTransform(scrollYProgress, [0.40, 0.45, 0.55, 0.60], [0, 1, 1, 0]);
  const noiseY = useTransform(scrollYProgress, [0.40, 0.45, 0.60], [50, 0, -50]);
  const noiseDisplay = useTransform(scrollYProgress, (v) => v < 0.38 || v > 0.63 ? "none" : "flex");

  const soundOpacity = useTransform(scrollYProgress, [0.65, 0.70, 0.75, 0.80], [0, 1, 1, 0]);
  const soundY = useTransform(scrollYProgress, [0.65, 0.70, 0.80], [50, 0, -50]);
  const soundDisplay = useTransform(scrollYProgress, (v) => v < 0.63 || v > 0.81 ? "none" : "flex");

  const ctaOpacity = useTransform(scrollYProgress, [0.83, 0.87, 0.90, 0.92], [0, 1, 1, 0]);
  const ctaY = useTransform(scrollYProgress, [0.83, 0.87, 0.92], [50, 0, -50]);
  const ctaDisplay = useTransform(scrollYProgress, (v) => v < 0.81 || v > 0.93 ? "none" : "flex");

  const creatorsOpacity = useTransform(scrollYProgress, [0.94, 0.98, 1], [0, 1, 1]);
  const creatorsY = useTransform(scrollYProgress, [0.94, 0.98], [50, 0]);
  const creatorsDisplay = useTransform(scrollYProgress, (v) => v < 0.93 ? "none" : "flex");

  // Navbar background fade in
  const navBg = useTransform(scrollYProgress, [0, 0.05], ["rgba(5,5,5,0)", "rgba(5,5,5,0.75)"]);
  const navBlur = useTransform(scrollYProgress, [0, 0.05], ["blur(0px)", "blur(12px)"]);

  return (
    <div className="bg-[#050505] min-h-screen text-white font-sans selection:bg-[#0050FF]/30">

      {/* Navigation */}
      <motion.nav
        className="fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-6 py-4 md:px-12"
        style={{ backgroundColor: navBg, backdropFilter: navBlur, WebkitBackdropFilter: navBlur }}
      >
        <div className="font-medium tracking-tight text-white/90 text-lg">
          StonkExchange
        </div>
        <div className="hidden md:flex items-center gap-8 text-sm text-white/60">
          <a href="/markets" className="hover:text-white transition-colors">Markets</a>
          <a href="/portfolio" className="hover:text-white transition-colors">Portfolio</a>
          <a href="/orders" className="hover:text-white transition-colors">Orders</a>
        </div>
        <div>
          <a href="/login" className="px-5 py-2 text-sm font-semibold rounded-full bg-transparent border border-[#0050FF]/40 hover:border-[#00D6FF] transition-all duration-300 relative group overflow-hidden inline-block">
            <span className="relative z-10">Start Trading</span>
            <div className="absolute inset-0 bg-gradient-to-r from-[#0050FF]/20 to-[#00D6FF]/20 opacity-0 group-hover:opacity-100 transition-opacity duration-300" />
          </a>
        </div>
      </motion.nav>

      {/* Scrollytelling Container */}
      <div ref={containerRef} className="relative h-[600vh]">

        {/* Sticky Canvas & Content */}
        <div className="sticky top-0 h-screen w-full overflow-hidden">

          {/* Subtle Background Glow */}
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,_#050815_0%,_transparent_70%)] opacity-60 pointer-events-none" />

          {/* HTML5 Canvas for Image Sequence */}
          <canvas
            ref={canvasRef}
            className="absolute inset-0 w-full h-full object-cover z-0"
          />

          {/* Overlay Content Blocks */}
          <div className="absolute inset-0 z-10 flex flex-col justify-center px-6 md:px-24 max-w-7xl mx-auto pointer-events-none">

            {/* HERO / INTRO (0-15%) */}
            <motion.div
              style={{ opacity: heroOpacity, y: heroY, display: heroDisplay }}
              className="absolute inset-0 flex-col items-center justify-center text-center mt-32"
            >
              <h1 className="text-5xl md:text-7xl lg:text-8xl font-bold tracking-tighter mb-4 text-transparent bg-clip-text bg-gradient-to-b from-white to-white/70">
                StonkExchange
              </h1>
              <p className="text-2xl md:text-3xl text-white/90 font-medium mb-6">
                Full-Fledged Trading Exchange
              </p>
              <p className="text-lg text-white/60 max-w-xl mx-auto">
                Complete stock trading platform with real-time market simulation, advanced price engines, and instant order fulfillment. Experience institutional-grade trading infrastructure.
              </p>
            </motion.div>

            {/* ENGINEERING REVEAL (15-40%) */}
            <motion.div
              style={{ opacity: engOpacity, y: engY, display: engDisplay }}
              className="absolute inset-0 flex-col justify-center items-start text-left max-w-md pointer-events-auto"
            >
              <h2 className="text-4xl md:text-5xl font-bold tracking-tight mb-6 bg-clip-text text-transparent bg-gradient-to-br from-white to-[#00D6FF]/80">
                Advanced Trading Infrastructure
              </h2>
              <div className="space-y-4 text-white/60 text-lg">
                <p>
                  Built-in market simulator generates realistic price movements with sophisticated algorithms and volatility modeling.
                </p>
                <p>
                  High-performance price engine processes real-time data with advanced order matching and instant trade execution.
                </p>
              </div>
            </motion.div>

            {/* NOISE CANCELLING (40-65%) */}
            <motion.div
              style={{ opacity: noiseOpacity, y: noiseY, display: noiseDisplay }}
              className="absolute inset-0 flex-col justify-center items-end text-right ml-auto max-w-md pointer-events-auto"
            >
              <h2 className="text-4xl md:text-5xl font-bold tracking-tight mb-6 bg-clip-text text-transparent bg-gradient-to-bl from-white to-[#0050FF]/80">
                Comprehensive Portfolio Management
              </h2>
              <ul className="space-y-4 text-white/60 text-lg">
                <li>Real-time portfolio tracking with live P&L calculations and performance analytics.</li>
                <li>Advanced order book visualization and market depth analysis for informed trading decisions.</li>
                <li>Complete order lifecycle management from placement to execution and settlement.</li>
              </ul>
            </motion.div>

            {/* SOUND & UPSCALING (65-85%) */}
            <motion.div
              style={{ opacity: soundOpacity, y: soundY, display: soundDisplay }}
              className="absolute inset-0 flex-col justify-center items-start text-left max-w-md pointer-events-auto"
            >
              <h2 className="text-4xl md:text-5xl font-bold tracking-tight mb-6 text-white/90 drop-shadow-[0_0_15px_rgba(255,255,255,0.1)]">
                Enterprise-Grade Reliability
              </h2>
              <div className="space-y-4 text-white/60 text-lg">
                <p>Robust PostgreSQL database with ACID transactions ensures data integrity and reliable trade processing.</p>
                <p>Comprehensive audit logging and transaction history provide complete transparency and regulatory compliance.</p>
              </div>
            </motion.div>

            {/* REASSEMBLY & CTA (80-95%) */}
            <motion.div
              style={{ opacity: ctaOpacity, y: ctaY, display: ctaDisplay }}
              className="absolute inset-0 flex-col items-center justify-center text-center pointer-events-auto"
            >
              <h2 className="text-5xl md:text-7xl font-bold tracking-tighter mb-4 text-white">
                Complete Trading Ecosystem. <span className="text-transparent bg-clip-text bg-gradient-to-r from-[#0050FF] to-[#00D6FF]">Built for Scale.</span>
              </h2>
              <p className="text-xl md:text-2xl text-white/80 mb-10">
                From market simulation to order fulfillment—everything you need for professional trading.
              </p>
              <div className="flex flex-col sm:flex-row gap-6 items-center">
                <a href="/login" className="px-8 py-4 bg-white text-black font-semibold rounded-full hover:scale-105 transition-transform duration-300 shadow-[0_0_30px_rgba(255,255,255,0.2)]">
                  Start Trading Now
                </a>
                <a href="/markets" className="text-white/60 hover:text-white underline decoration-white/30 underline-offset-4 transition-colors">
                  Explore Markets
                </a>
              </div>
              <p className="mt-8 text-sm text-white/40">
                Full-stack trading platform with market simulation, price engines, and complete order lifecycle management.
              </p>
            </motion.div>

            {/* CREATORS (95-100%) */}
            <motion.div
              style={{ opacity: creatorsOpacity, y: creatorsY, display: creatorsDisplay }}
              className="absolute inset-0 flex-col items-center justify-end text-center pb-24 pointer-events-auto"
            >
              <h3 className="text-2xl md:text-3xl font-bold tracking-tight mb-6 text-white/80">
                Created By
              </h3>
              <div className="space-y-2 text-white/60 text-lg md:text-xl font-medium">
                <p>Muhammad Hashim <span className="text-[#00D6FF] ml-2">24L-0775</span></p>
                <p>Abdullah Kamran <span className="text-[#00D6FF] ml-2">24L-0581</span></p>
                <p>Muhammad Musab <span className="text-[#00D6FF] ml-2">24L-0511</span></p>
              </div>
            </motion.div>

          </div>
        </div>
      </div>
    </div>
  );
}
